import Foundation

/// Status byte of the oscilloscope's and the data logger's Metadata characteristic.
public enum AcquisitionStatus: Equatable, Sendable {
    /// Finished; the samples can be fetched (or follow right away).
    case done
    case sampling
    /// Data logger only: the memory is full and logging has stopped.
    case bufferFull
    case error
    case unknown(UInt8)

    public init(byte: UInt8) {
        switch byte {
        case 0: self = .done
        case 1: self = .sampling
        case 2: self = .bufferFull
        case 255: self = .error
        default: self = .unknown(byte)
        }
    }
}

/// Raw samples as the oscilloscope and the data logger send them: signed 16-bit values,
/// little-endian, several per notification. The real value is `sample * scale`, with the
/// scale taken from the Metadata characteristic.
public enum SampleDecoder {
    /// `nil` for a value with an odd number of bytes, which cannot be a list of samples.
    public static func samples(from data: Data) -> [Int16]? {
        let reader = ByteReader(data)
        guard reader.count % 2 == 0 else { return nil }
        return (0..<(reader.count / 2)).map { reader.int16(at: $0 * 2) }
    }
}

/// What a set of samples looks like: extremes, average and, for a repeating signal, its
/// frequency.
public struct WaveformSummary: Equatable, Sendable {
    public var minimum: Double
    public var maximum: Double
    public var mean: Double
    /// `nil` when the samples do not cross their mid level often enough to tell.
    public var frequency: Double?

    public var peakToPeak: Double { maximum - minimum }

    /// - Parameter sampleRate: samples per second; pass `nil` (or 0) for data without a
    ///   meaningful frequency, such as a log.
    public init?(samples: [Double], sampleRate: Double? = nil) {
        let finite = samples.filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else { return nil }
        minimum = low
        maximum = high
        mean = finite.reduce(0, +) / Double(finite.count)
        frequency = nil
        if let sampleRate, sampleRate > 0 {
            frequency = WaveformSummary.frequency(of: finite, sampleRate: sampleRate, low: low, high: high)
        }
    }

    /// Counts rising crossings of the mid level, with a hysteresis band so that noise on a
    /// slow edge is not counted several times. The frequency is taken from the distance
    /// between the first and the last crossing, which is more exact than crossings per window.
    private static func frequency(of samples: [Double], sampleRate: Double, low: Double, high: Double) -> Double? {
        let span = high - low
        guard span > 0, samples.count >= 8 else { return nil }
        let middle = (high + low) / 2
        let upper = middle + span * 0.1
        let lower = middle - span * 0.1

        var crossings: [Double] = []
        var armed = false
        var previous = samples[0]
        for (index, value) in samples.enumerated().dropFirst() {
            if value < lower {
                armed = true
            } else if armed, previous < middle, value >= middle || value > upper {
                // Interpolate where exactly between the two samples the mid level was crossed.
                let step = value - previous
                let fraction = step != 0 ? (middle - previous) / step : 0
                crossings.append(Double(index - 1) + min(max(fraction, 0), 1))
                armed = false
            }
            previous = value
        }
        guard crossings.count >= 2, let first = crossings.first, let last = crossings.last, last > first else {
            return nil
        }
        return Double(crossings.count - 1) * sampleRate / (last - first)
    }
}
