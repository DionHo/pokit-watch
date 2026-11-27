import Foundation

/// What starts an oscilloscope capture.
public enum ScopeTrigger: Equatable, Sendable {
    /// Capture immediately.
    case freeRunning
    /// Wait until the signal rises through `level` (volts or amps).
    case risingEdge(level: Float)
    case fallingEdge(level: Float)

    var command: UInt8 {
        switch self {
        case .freeRunning: return 0
        case .risingEdge: return 1
        case .fallingEdge: return 2
        }
    }

    var level: Float {
        switch self {
        case .freeRunning: return 0
        case .risingEdge(let level), .fallingEdge(let level): return level
        }
    }
}

/// Value written to the oscilloscope's Settings characteristic. Writing it arms one capture;
/// the device answers with Metadata and then the samples.
public struct ScopeSettings: Equatable, Sendable {
    /// The modes the oscilloscope can capture. Their raw values are the same as in the
    /// multimeter.
    public static let modes: [MultimeterMode] = [.dcVoltage, .acVoltage, .dcCurrent, .acCurrent]

    public var trigger: ScopeTrigger
    public var mode: MultimeterMode
    /// Index into the product's range table. The oscilloscope has no auto-range.
    public var rangeIndex: UInt8
    /// Length of the capture in microseconds.
    public var window: UInt32
    public var sampleCount: UInt16

    public init(trigger: ScopeTrigger, mode: MultimeterMode, rangeIndex: UInt8, window: UInt32, sampleCount: UInt16) {
        self.trigger = trigger
        self.mode = mode
        self.rangeIndex = rangeIndex
        self.window = window
        self.sampleCount = sampleCount
    }

    /// Settings that put the oscilloscope back to idle, cancelling a capture that is still
    /// waiting for its trigger.
    public static let idle = ScopeSettings(trigger: .freeRunning, mode: .idle, rangeIndex: 0, window: 0, sampleCount: 0)

    /// 13 bytes: command, trigger level (float), mode, range, window (uint32, µs),
    /// sample count (uint16).
    public func encoded() -> Data {
        var data = Data(capacity: 13)
        data.append(trigger.command)
        data.appendLittleEndian(trigger.level)
        data.append(mode.rawValue)
        data.append(rangeIndex)
        data.appendLittleEndian(window)
        data.appendLittleEndian(sampleCount)
        return data
    }
}

/// Value of the oscilloscope's Metadata characteristic: what the capture that follows is.
public struct ScopeMetadata: Equatable, Sendable {
    public var status: AcquisitionStatus
    /// Multiply each raw sample by this to get volts or amps.
    public var scale: Double
    public var modeByte: UInt8
    public var rangeIndex: UInt8
    /// Length of the capture in microseconds.
    public var window: UInt32
    public var sampleCount: Int
    /// Samples per second.
    public var samplingRate: UInt32

    /// Decodes the 17-byte value. The Pokit Pro appends bytes of unknown meaning, which are
    /// ignored; shorter values are rejected.
    public init?(data: Data) {
        let reader = ByteReader(data)
        guard reader.count >= 17 else { return nil }
        status = AcquisitionStatus(byte: reader.uint8(at: 0))
        scale = Double(reader.float32(at: 1))
        modeByte = reader.uint8(at: 5)
        rangeIndex = reader.uint8(at: 6)
        window = reader.uint32(at: 7)
        sampleCount = Int(reader.uint16(at: 11))
        samplingRate = reader.uint32(at: 13)
    }
}

/// Picks the range for the next capture from what the last one showed. The oscilloscope
/// has no auto-range of its own, so the app steps through the ranges itself.
public enum ScopeRangeAdvisor {
    /// - Parameters:
    ///   - current: index of the range the capture was taken in.
    ///   - peak: largest absolute value in the capture, in base units.
    ///   - ranges: the product's ranges for the mode, lowest first.
    /// - Returns: the index to use next; `current` if it still fits.
    public static func nextRange(current: UInt8, peak: Double, ranges: [MeterRange]) -> UInt8 {
        guard let position = ranges.firstIndex(where: { $0.index == current }) else {
            return ranges.last?.index ?? current
        }
        guard peak.isFinite else {
            return ranges.last?.index ?? current
        }
        // Too close to the limit (or clipped): go up as far as needed in one step.
        if peak > ranges[position].fullScale * 0.9 {
            let fitting = ranges[(position + 1)...].first { peak <= $0.fullScale * 0.9 }
            return (fitting ?? ranges.last ?? ranges[position]).index
        }
        // Comfortably inside the next lower range: go down one step at a time, with a margin
        // so the choice does not flip back and forth on a signal near the border.
        if position > 0, peak < ranges[position - 1].fullScale * 0.6 {
            return ranges[position - 1].index
        }
        return current
    }
}
