import Foundation

/// Value of the Status service's Device Characteristics characteristic (20 bytes, read once).
public struct DeviceCharacteristics: Equatable, Sendable {
    public var firmwareMajor: UInt8
    public var firmwareMinor: UInt8
    /// Limits as reported by the device (volts, amps, kΩ, kHz, samples).
    public var maximumVoltage: UInt16
    public var maximumCurrent: UInt16
    public var maximumResistance: UInt16
    public var maximumSamplingRate: UInt16
    public var samplingBufferSize: UInt16
    public var capabilityMask: UInt16
    /// `AA:BB:CC:DD:EE:FF`
    public var macAddress: String

    public var firmwareVersion: String {
        "\(firmwareMajor).\(firmwareMinor)"
    }

    public init?(data: Data) {
        let reader = ByteReader(data)
        guard reader.count >= 20 else { return nil }
        firmwareMajor = reader.uint8(at: 0)
        firmwareMinor = reader.uint8(at: 1)
        maximumVoltage = reader.uint16(at: 2)
        maximumCurrent = reader.uint16(at: 4)
        maximumResistance = reader.uint16(at: 6)
        maximumSamplingRate = reader.uint16(at: 8)
        samplingBufferSize = reader.uint16(at: 10)
        capabilityMask = reader.uint16(at: 12)
        macAddress = reader.slice(at: 14, count: 6)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
    }
}

public enum BatteryStatus: UInt8, Sendable {
    case low = 0
    case good = 1
}

/// Position of the Pokit Pro's physical mode switch.
public enum SwitchPosition: UInt8, Sendable {
    /// "V"
    case voltage = 0
    /// Resistance, low current, capacitance, diode
    case multiMode = 1
    /// "A"
    case highCurrent = 2

    /// Whether `mode` is expected to work in this position.
    ///
    /// The switch is not documented by Pokit; this follows the labels on the device, and the
    /// app only uses it for a hint, never to block a mode.
    public func isExpectedToSupport(_ mode: MultimeterMode) -> Bool {
        switch mode {
        case .idle, .temperature:
            return true
        case .dcVoltage, .acVoltage:
            return self == .voltage
        case .dcCurrent, .acCurrent:
            return self == .multiMode || self == .highCurrent
        case .resistance, .diode, .continuity, .capacitance, .externalTemperature:
            return self == .multiMode
        }
    }
}

public enum ChargingStatus: UInt8, Sendable {
    case discharging = 0
    case charging = 1
    case charged = 2
}

/// Value of the Status characteristic. The Pokit Meter sends 5 bytes; the Pokit Pro sends 8,
/// adding battery status, switch position and charging status.
public struct DeviceStatus: Equatable, Sendable {
    /// What the device is doing: 0 idle, 1–8 multimeter modes, 9 oscilloscope, 10 data logger.
    public var activityByte: UInt8
    public var batteryVoltage: Double
    public var batteryStatus: BatteryStatus?
    public var switchPosition: SwitchPosition?
    public var chargingStatus: ChargingStatus?

    public init?(data: Data) {
        let reader = ByteReader(data)
        guard reader.count >= 5 else { return nil }
        activityByte = reader.uint8(at: 0)
        batteryVoltage = Double(reader.float32(at: 1))
        batteryStatus = reader.count >= 6 ? BatteryStatus(rawValue: reader.uint8(at: 5)) : nil
        switchPosition = reader.count >= 7 ? SwitchPosition(rawValue: reader.uint8(at: 6)) : nil
        chargingStatus = reader.count >= 8 ? ChargingStatus(rawValue: reader.uint8(at: 7)) : nil
    }

    /// Rough state of charge in `0...1`, estimated from the battery voltage.
    ///
    /// Pokit publishes no discharge curve, so this is a straight line between an empty and a
    /// full voltage for each product's cell type: good enough for a battery icon, no more.
    public func estimatedBatteryLevel(for product: PokitProduct) -> Double {
        let empty: Double
        let full: Double
        switch product {
        case .meter: // 3 V lithium coin cell
            empty = 2.2
            full = 3.0
        case .pro: // Li-ion cell
            empty = 3.4
            full = 4.15
        }
        guard batteryVoltage.isFinite else { return 0 }
        return min(1, max(0, (batteryVoltage - empty) / (full - empty)))
    }
}

/// State of the Pokit Pro's button, from the Button Press characteristic.
public enum ButtonEvent: UInt8, Sendable {
    case released = 0
    case pressed = 1
    case held = 2

    /// The characteristic has two bytes; the second one carries the button state.
    public init?(data: Data) {
        let reader = ByteReader(data)
        guard reader.count >= 2, let event = ButtonEvent(rawValue: reader.uint8(at: 1)) else { return nil }
        self = event
    }
}

/// Helpers for the string characteristics (device name, Device Information service).
public enum PokitText {
    /// Longest device name the Pokit accepts, in UTF-8 bytes.
    public static let maximumNameLength = 11

    /// Decodes a UTF-8 string value. The Pokit Pro pads some strings with NUL bytes.
    public static func decode(_ data: Data) -> String? {
        let trimmed = data.prefix { $0 != 0 }
        guard let text = String(data: Data(trimmed), encoding: .utf8) else { return nil }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
