import Foundation

/// What the data logger can record. The raw values are the logger's own numbering, which
/// differs from the multimeter's for temperature.
public enum LoggerMode: UInt8, CaseIterable, Sendable, Codable {
    case dcVoltage = 1
    case acVoltage = 2
    case dcCurrent = 3
    case acCurrent = 4
    case temperature = 5

    /// The same quantity as a multimeter mode, for titles, units and range tables.
    public var multimeterMode: MultimeterMode {
        switch self {
        case .dcVoltage: return .dcVoltage
        case .acVoltage: return .acVoltage
        case .dcCurrent: return .dcCurrent
        case .acCurrent: return .acCurrent
        case .temperature: return .temperature
        }
    }
}

/// The two wire formats of the data logger. The Pokit Meter counts the interval in seconds
/// (16 bit), the Pokit Pro in milliseconds (32 bit), which shifts everything after it.
public enum LoggerLayout: Equatable, Sendable {
    case meter
    case pro

    public init(product: PokitProduct) {
        self = product == .pro ? .pro : .meter
    }

    /// The layout a Metadata value of this length uses, if it is long enough to be one.
    public init?(metadataLength: Int) {
        if metadataLength >= 23 {
            self = .pro
        } else if metadataLength >= 15 {
            self = .meter
        } else {
            return nil
        }
    }
}

public enum LoggerCommand: UInt8, Sendable {
    case start = 0
    case stop = 1
    /// Asks the device to send Metadata and all samples recorded so far.
    case refresh = 2
}

/// Value written to the data logger's Settings characteristic.
public struct LoggerSettings: Equatable, Sendable {
    public var command: LoggerCommand
    /// Raw mode byte (`LoggerMode`, or 0 where the command ignores it).
    public var modeByte: UInt8
    public var rangeIndex: UInt8
    /// Time between samples in seconds.
    public var interval: UInt32
    /// Opaque to the device, which hands it back in Metadata. The app stores the start time
    /// here (seconds since 1970) so a log can be dated after reconnecting.
    public var timestamp: UInt32

    public init(command: LoggerCommand, modeByte: UInt8 = 0, rangeIndex: UInt8 = 0, interval: UInt32 = 0, timestamp: UInt32 = 0) {
        self.command = command
        self.modeByte = modeByte
        self.rangeIndex = rangeIndex
        self.interval = interval
        self.timestamp = timestamp
    }

    public static func start(mode: LoggerMode, rangeIndex: UInt8, interval: UInt32, timestamp: UInt32) -> LoggerSettings {
        LoggerSettings(command: .start, modeByte: mode.rawValue, rangeIndex: rangeIndex, interval: interval, timestamp: timestamp)
    }

    public static let stop = LoggerSettings(command: .stop)
    public static let refresh = LoggerSettings(command: .refresh)

    /// Longest interval both layouts can express (the Meter's 16-bit seconds).
    public static let maximumInterval: UInt32 = 3600

    /// 11 bytes (Meter) or 13 bytes (Pro): command, two reserved bytes, mode, range,
    /// interval, timestamp.
    public func encoded(layout: LoggerLayout) -> Data {
        var data = Data(capacity: 13)
        data.append(command.rawValue)
        data.appendLittleEndian(UInt16(0))
        data.append(modeByte)
        data.append(rangeIndex)
        switch layout {
        case .meter:
            data.appendLittleEndian(UInt16(clamping: interval))
        case .pro:
            let milliseconds = interval.multipliedReportingOverflow(by: 1000)
            data.appendLittleEndian(milliseconds.overflow ? UInt32.max : milliseconds.partialValue)
        }
        data.appendLittleEndian(timestamp)
        return data
    }
}

/// Value of the data logger's Metadata characteristic.
public struct LoggerMetadata: Equatable, Sendable {
    public var status: AcquisitionStatus
    /// Multiply each raw sample by this to get the value in base units.
    public var scale: Double
    public var modeByte: UInt8
    public var rangeIndex: UInt8
    /// Time between samples in seconds.
    public var interval: Double
    public var sampleCount: Int
    /// The value given when the log was started; this app puts the start time there.
    public var timestamp: UInt32
    public var layout: LoggerLayout

    /// Decodes the 15-byte (Meter) or 23-byte (Pro) value; shorter values are rejected.
    public init?(data: Data) {
        let reader = ByteReader(data)
        guard let layout = LoggerLayout(metadataLength: reader.count) else { return nil }
        self.layout = layout
        status = AcquisitionStatus(byte: reader.uint8(at: 0))
        scale = Double(reader.float32(at: 1))
        modeByte = reader.uint8(at: 5)
        rangeIndex = reader.uint8(at: 6)
        switch layout {
        case .meter:
            interval = Double(reader.uint16(at: 7))
            sampleCount = Int(reader.uint16(at: 9))
            timestamp = reader.uint32(at: 11)
        case .pro:
            interval = Double(reader.uint32(at: 7)) / 1000
            sampleCount = Int(reader.uint16(at: 11))
            // Bytes 13...18 are not understood.
            timestamp = reader.uint32(at: 19)
        }
    }

    public var mode: LoggerMode? {
        LoggerMode(rawValue: modeByte)
    }

    /// When the log was started, if the timestamp looks like a date this app wrote.
    public var startDate: Date? {
        // Before 2020 it is not one of ours (or the device lost it).
        timestamp > 1_577_836_800 ? Date(timeIntervalSince1970: TimeInterval(timestamp)) : nil
    }
}
