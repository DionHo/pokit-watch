/// Everything the measurement screen shows for one reading, already formatted.
public struct MeterDisplay: Equatable, Sendable {
    public enum Condition: Equatable, Sendable {
        case normal
        /// Input is outside the range.
        case overload
        /// The device reported an error for this mode.
        case error
    }

    public var value: DisplayValue
    public var condition: Condition
    public var mode: MultimeterMode?
    /// Label of the range the value was measured in, e.g. `6 V`. `nil` for modes without ranges.
    public var rangeLabel: String?
    public var isAutoRange: Bool?
    /// Set in continuity mode only.
    public var hasContinuity: Bool?

    public static let overloadText = "OL"
    public static let errorText = "ERR"

    /// What to show before the first reading arrives.
    public static func placeholder(for mode: MultimeterMode) -> MeterDisplay {
        MeterDisplay(
            value: DisplayValue(number: ValueFormatter.placeholder, unit: mode.unit),
            condition: .normal,
            mode: mode,
            rangeLabel: nil,
            isAutoRange: nil,
            hasContinuity: nil
        )
    }

    public init(
        value: DisplayValue,
        condition: Condition,
        mode: MultimeterMode?,
        rangeLabel: String?,
        isAutoRange: Bool?,
        hasContinuity: Bool?
    ) {
        self.value = value
        self.condition = condition
        self.mode = mode
        self.rangeLabel = rangeLabel
        self.isAutoRange = isAutoRange
        self.hasContinuity = hasContinuity
    }

    public init(reading: MultimeterReading, product: PokitProduct) {
        let mode = reading.mode
        let unit = mode?.unit ?? ""
        let range = mode.flatMap { product.range(for: $0, index: reading.rangeIndex) }

        self.mode = mode
        self.rangeLabel = range?.label(unit: unit)
        self.isAutoRange = reading.isAutoRange
        self.hasContinuity = reading.hasContinuity

        if reading.isError {
            condition = .error
            value = DisplayValue(number: MeterDisplay.errorText, unit: unit)
        } else if reading.isOverload {
            condition = .overload
            value = DisplayValue(number: MeterDisplay.overloadText, unit: unit)
        } else {
            condition = .normal
            value = MeterDisplay.format(reading.value, mode: mode, range: range)
        }
    }

    /// Formats a value for `mode`. With a known range the decimal point is fixed by the range,
    /// as on a bench meter; otherwise the prefix follows the value.
    public static func format(_ value: Double, mode: MultimeterMode?, range: MeterRange? = nil) -> DisplayValue {
        guard let mode else {
            return ValueFormatter.format(value, unit: "")
        }
        if let range {
            return ValueFormatter.format(value, unit: mode.unit, fullScale: range.fullScale)
        }
        switch mode {
        case .idle:
            return DisplayValue(number: ValueFormatter.placeholder, unit: "")
        case .dcVoltage, .acVoltage:
            return ValueFormatter.format(value, unit: mode.unit, minimum: .milli, maximum: .none)
        case .dcCurrent, .acCurrent:
            return ValueFormatter.format(value, unit: mode.unit, minimum: .micro, maximum: .none)
        case .resistance, .continuity:
            return ValueFormatter.format(value, unit: mode.unit, minimum: .none)
        case .diode:
            return ValueFormatter.format(value, unit: mode.unit, fullScale: 2)
        case .capacitance:
            return ValueFormatter.format(value, unit: mode.unit, maximum: .milli)
        case .temperature, .externalTemperature:
            return ValueFormatter.formatPlain(value, unit: mode.unit, decimals: 1)
        }
    }
}

/// Running minimum / maximum of the readings since the last reset.
public struct ReadingStatistics: Equatable, Sendable {
    public private(set) var minimum: Double?
    public private(set) var maximum: Double?
    public private(set) var count = 0

    public init() {}

    public mutating func add(_ value: Double) {
        guard value.isFinite else { return }
        minimum = Swift.min(minimum ?? value, value)
        maximum = Swift.max(maximum ?? value, value)
        count += 1
    }

    public mutating func reset() {
        self = ReadingStatistics()
    }
}
