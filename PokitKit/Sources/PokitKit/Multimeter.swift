import Foundation

/// Multimeter modes. The raw value is the byte used in the Settings and Reading characteristics.
public enum MultimeterMode: UInt8, CaseIterable, Sendable, Codable {
    case idle = 0
    case dcVoltage = 1
    case acVoltage = 2
    case dcCurrent = 3
    case acCurrent = 4
    case resistance = 5
    case diode = 6
    case continuity = 7
    case temperature = 8
    /// Pokit Pro only.
    case capacitance = 9
    /// Temperature through an external probe. Pokit Pro only.
    case externalTemperature = 10

    /// English name; the app uses it as the localisation key.
    public var title: String {
        switch self {
        case .idle: return "Idle"
        case .dcVoltage: return "DC Voltage"
        case .acVoltage: return "AC Voltage"
        case .dcCurrent: return "DC Current"
        case .acCurrent: return "AC Current"
        case .resistance: return "Resistance"
        case .diode: return "Diode"
        case .continuity: return "Continuity"
        case .temperature: return "Temperature"
        case .capacitance: return "Capacitance"
        case .externalTemperature: return "Ext. Temperature"
        }
    }

    /// Compact label in multimeter notation, the same in every language.
    public var symbol: String {
        switch self {
        case .idle: return "—"
        case .dcVoltage: return "V⎓"
        case .acVoltage: return "V~"
        case .dcCurrent: return "A⎓"
        case .acCurrent: return "A~"
        case .resistance: return "Ω"
        case .diode: return "▶|"
        case .continuity: return "•))"
        case .temperature: return "°C"
        case .capacitance: return "F"
        case .externalTemperature: return "°C ext"
        }
    }

    /// Base unit of the reading's value.
    public var unit: String {
        switch self {
        case .idle: return ""
        case .dcVoltage, .acVoltage, .diode: return "V"
        case .dcCurrent, .acCurrent: return "A"
        case .resistance, .continuity: return "Ω"
        case .temperature, .externalTemperature: return "°C"
        case .capacitance: return "F"
        }
    }

    /// Whether the mode has selectable ranges (and reports auto-range in the status byte).
    public var hasRanges: Bool {
        switch self {
        case .dcVoltage, .acVoltage, .dcCurrent, .acCurrent, .resistance, .capacitance:
            return true
        case .idle, .diode, .continuity, .temperature, .externalTemperature:
            return false
        }
    }

    public var isAC: Bool {
        self == .acVoltage || self == .acCurrent
    }
}

/// One selectable range: the index sent to the device and the largest value it measures.
public struct MeterRange: Equatable, Hashable, Sendable, Identifiable {
    /// Value of the range byte.
    public let index: UInt8
    /// Upper limit in base units (V, A, Ω or F).
    public let fullScale: Double

    public var id: UInt8 { index }

    public init(index: UInt8, fullScale: Double) {
        self.index = index
        self.fullScale = fullScale
    }

    /// Short label such as `300 mV` or `1.5 kΩ`.
    public func label(unit: String) -> String {
        let prefix = SIPrefix.fitting(fullScale)
        let scaled = fullScale / prefix.factor
        let number = scaled == scaled.rounded()
            ? String(format: "%.0f", scaled)
            : String(format: "%g", scaled)
        return "\(number) \(prefix.symbol)\(unit)"
    }
}

/// Range choice for a measurement.
public enum RangeSelection: Equatable, Hashable, Sendable {
    case auto
    case fixed(UInt8)

    /// The byte that means "auto-range" on the wire.
    public static let autoByte: UInt8 = 0xFF

    public var byte: UInt8 {
        switch self {
        case .auto: return RangeSelection.autoByte
        case .fixed(let index): return index
        }
    }

    public init(byte: UInt8) {
        self = byte == RangeSelection.autoByte ? .auto : .fixed(byte)
    }
}

/// Value written to the multimeter Settings characteristic. Writing it starts the measurement;
/// writing mode `.idle` stops it.
public struct MultimeterSettings: Equatable, Sendable {
    public var mode: MultimeterMode
    public var range: RangeSelection
    /// Time between readings in milliseconds.
    public var updateInterval: UInt32

    public init(mode: MultimeterMode, range: RangeSelection = .auto, updateInterval: UInt32 = 250) {
        self.mode = mode
        self.range = range
        self.updateInterval = updateInterval
    }

    /// Settings that stop the measurement.
    public static let idle = MultimeterSettings(mode: .idle, range: .auto, updateInterval: 1000)

    /// 6 bytes: mode, range, update interval (uint32 LE, ms).
    public func encoded() -> Data {
        var data = Data(capacity: 6)
        data.append(mode.rawValue)
        // Modes without ranges ignore the byte; "auto" is what existing clients send for them.
        data.append(mode.hasRanges ? range.byte : RangeSelection.autoByte)
        data.appendLittleEndian(updateInterval)
        return data
    }
}

/// Value of the multimeter Reading characteristic.
public struct MultimeterReading: Equatable, Sendable {
    /// Status byte. Its meaning depends on the mode: auto-range on/off for ranged modes,
    /// continuity yes/no in continuity mode, 255 for an error in any mode.
    public var statusByte: UInt8
    /// Measured value in base units (V, A, Ω, °C, F).
    public var value: Double
    /// Mode byte as sent by the device.
    public var modeByte: UInt8
    /// Index of the range the value was measured in (also reported while auto-ranging).
    public var rangeIndex: UInt8

    public static let errorStatus: UInt8 = 0xFF

    public init(statusByte: UInt8, value: Double, modeByte: UInt8, rangeIndex: UInt8) {
        self.statusByte = statusByte
        self.value = value
        self.modeByte = modeByte
        self.rangeIndex = rangeIndex
    }

    /// Decodes the 7-byte characteristic value. Longer values are accepted (newer firmware may
    /// append fields); shorter ones are rejected.
    public init?(data: Data) {
        let reader = ByteReader(data)
        guard reader.count >= 7 else { return nil }
        statusByte = reader.uint8(at: 0)
        value = Double(reader.float32(at: 1))
        modeByte = reader.uint8(at: 5)
        rangeIndex = reader.uint8(at: 6)
    }

    /// The mode, or `nil` if the device reports one this app does not know.
    public var mode: MultimeterMode? {
        MultimeterMode(rawValue: modeByte)
    }

    public var isError: Bool {
        statusByte == MultimeterReading.errorStatus
    }

    /// Out-of-range input. Pokit documents no overload flag; the value itself turns
    /// non-finite (or absurdly large), so that is what is checked here.
    public var isOverload: Bool {
        !value.isFinite || abs(value) > 1e12
    }

    /// `true`/`false` for modes with ranges, `nil` otherwise.
    public var isAutoRange: Bool? {
        guard let mode, mode.hasRanges, !isError else { return nil }
        return statusByte == 1
    }

    /// `true`/`false` in continuity mode, `nil` otherwise.
    public var hasContinuity: Bool? {
        guard mode == .continuity, !isError else { return nil }
        return statusByte == 1
    }
}
