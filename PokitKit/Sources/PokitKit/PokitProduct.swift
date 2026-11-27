/// The Pokit models this app knows. They are told apart by the Status service UUID they
/// advertise, and differ in range tables and in a few extra features.
public enum PokitProduct: String, CaseIterable, Sendable, Codable {
    case meter
    case pro

    public var displayName: String {
        switch self {
        case .meter: return "Pokit Meter"
        case .pro: return "Pokit Pro"
        }
    }

    public var statusServiceUUID: String {
        switch self {
        case .meter: return PokitUUID.statusServiceMeter
        case .pro: return PokitUUID.statusServicePro
        }
    }

    /// Identifies the product from a Status service UUID (case-insensitive).
    public init?(statusServiceUUID uuid: String) {
        let wanted = uuid.uppercased()
        guard let match = PokitProduct.allCases.first(where: { $0.statusServiceUUID == wanted }) else {
            return nil
        }
        self = match
    }

    /// Measurement modes offered to the user, in menu order.
    public var measurementModes: [MultimeterMode] {
        switch self {
        case .meter:
            return [.dcVoltage, .acVoltage, .dcCurrent, .acCurrent, .resistance, .continuity, .diode, .temperature]
        case .pro:
            return [.dcVoltage, .acVoltage, .dcCurrent, .acCurrent, .resistance, .continuity, .diode,
                    .capacitance, .temperature, .externalTemperature]
        }
    }

    /// Flashing the LED to find the device only works on the Pokit Meter.
    public var supportsFlashLED: Bool { self == .meter }

    /// The Pokit Pro has a torch, a button and a physical mode switch.
    public var hasTorch: Bool { self == .pro }

    /// Selectable ranges for `mode`, lowest first. Empty for modes without ranges.
    public func ranges(for mode: MultimeterMode) -> [MeterRange] {
        let limits: [Double]
        switch (self, mode) {
        case (.meter, .dcVoltage), (.meter, .acVoltage):
            limits = [0.3, 2, 6, 12, 30, 60]
        case (.meter, .dcCurrent), (.meter, .acCurrent):
            limits = [0.01, 0.03, 0.15, 0.3, 2]
        case (.meter, .resistance):
            limits = [160, 330, 890, 1_500, 10_000, 100_000, 470_000, 1_000_000]
        case (.pro, .dcVoltage), (.pro, .acVoltage):
            limits = [0.25, 2, 10, 30, 60, 125, 400, 600]
        case (.pro, .dcCurrent), (.pro, .acCurrent):
            limits = [0.0005, 0.002, 0.01, 0.125, 0.3, 3, 10]
        case (.pro, .resistance):
            limits = [30, 75, 400, 5_000, 10_000, 15_000, 40_000, 500_000, 700_000, 1_000_000, 3_000_000]
        case (.pro, .capacitance):
            limits = [100e-9, 10e-6, 1e-3]
        default:
            limits = []
        }
        return limits.enumerated().map { MeterRange(index: UInt8($0.offset), fullScale: $0.element) }
    }

    /// The range with the given index, if `mode` has one.
    public func range(for mode: MultimeterMode, index: UInt8) -> MeterRange? {
        let all = ranges(for: mode)
        return Int(index) < all.count ? all[Int(index)] : nil
    }
}
