import Foundation

/// A measurement split into the text for the large digits and the unit shown next to it,
/// e.g. `number: "12.34"`, `unit: "mV"`.
public struct DisplayValue: Equatable, Sendable {
    public var number: String
    public var unit: String

    public init(number: String, unit: String) {
        self.number = number
        self.unit = unit
    }

    /// Single-line form, e.g. `"12.34 mV"`.
    public var text: String {
        unit.isEmpty ? number : "\(number) \(unit)"
    }
}

/// Engineering prefixes used on the display. The raw value is the power of 1000.
public enum SIPrefix: Int, CaseIterable, Comparable, Sendable {
    case pico = -4
    case nano = -3
    case micro = -2
    case milli = -1
    case none = 0
    case kilo = 1
    case mega = 2

    public var symbol: String {
        switch self {
        case .pico: return "p"
        case .nano: return "n"
        case .micro: return "µ"
        case .milli: return "m"
        case .none: return ""
        case .kilo: return "k"
        case .mega: return "M"
        }
    }

    public var factor: Double {
        switch self {
        case .pico: return 1e-12
        case .nano: return 1e-9
        case .micro: return 1e-6
        case .milli: return 1e-3
        case .none: return 1
        case .kilo: return 1e3
        case .mega: return 1e6
        }
    }

    public static func < (lhs: SIPrefix, rhs: SIPrefix) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The prefix that brings `magnitude` into `1..<1000`, limited to `minimum...maximum`.
    public static func fitting(
        _ magnitude: Double,
        minimum: SIPrefix = .pico,
        maximum: SIPrefix = .mega
    ) -> SIPrefix {
        guard magnitude.isFinite, magnitude > 0 else { return max(minimum, min(.none, maximum)) }
        var best = minimum
        for prefix in SIPrefix.allCases where prefix >= minimum && prefix <= maximum {
            // The tiny tolerance keeps values such as 0.3 (stored as 0.29999...) on the intended side.
            if magnitude >= prefix.factor * (1 - 1e-9) {
                best = prefix
            }
        }
        return best
    }
}

public enum ValueFormatter {
    /// Text shown when there is no usable number (overload, no reading yet).
    public static let placeholder = "–––"

    /// Formats `value` (in base units) the way a bench multimeter does for a fixed range:
    /// prefix and number of decimals come from the range's full-scale value, so the decimal
    /// point stays put while the reading changes.
    ///
    /// `format(0.01234, unit: "V", fullScale: 0.3)` gives `12.3 mV`,
    /// `format(1.5, unit: "V", fullScale: 6)` gives `1.500 V`.
    public static func format(
        _ value: Double,
        unit: String,
        fullScale: Double,
        digits: Int = 4
    ) -> DisplayValue {
        guard fullScale.isFinite, fullScale > 0 else {
            return format(value, unit: unit, digits: digits)
        }
        let prefix = SIPrefix.fitting(fullScale)
        let decimals = max(0, digits - integerDigits(fullScale / prefix.factor))
        return render(value, unit: unit, prefix: prefix, decimals: decimals)
    }

    /// Formats `value` (in base units) with a prefix chosen from the value itself.
    /// Use `minimum` to stop tiny noise readings from dropping into µ/n/p.
    public static func format(
        _ value: Double,
        unit: String,
        digits: Int = 4,
        minimum: SIPrefix = .pico,
        maximum: SIPrefix = .mega
    ) -> DisplayValue {
        guard value.isFinite else { return DisplayValue(number: placeholder, unit: unit) }
        var prefix = SIPrefix.fitting(abs(value), minimum: minimum, maximum: maximum)
        var decimals = max(0, digits - integerDigits(abs(value) / prefix.factor))
        // Rounding can push e.g. 999.96 up to 1000.0; move to the next prefix in that case.
        let rounded = roundTo(abs(value) / prefix.factor, decimals: decimals)
        if rounded >= 1000, let next = SIPrefix(rawValue: prefix.rawValue + 1), next <= maximum {
            prefix = next
            decimals = max(0, digits - integerDigits(abs(value) / prefix.factor))
        }
        return render(value, unit: unit, prefix: prefix, decimals: decimals)
    }

    /// Formats a value without any prefix and with a fixed number of decimals (temperature etc.).
    public static func formatPlain(_ value: Double, unit: String, decimals: Int) -> DisplayValue {
        render(value, unit: unit, prefix: .none, decimals: decimals, showPrefix: false)
    }

    // MARK: - Helpers

    private static func render(
        _ value: Double,
        unit: String,
        prefix: SIPrefix,
        decimals: Int,
        showPrefix: Bool = true
    ) -> DisplayValue {
        let fullUnit = showPrefix ? prefix.symbol + unit : unit
        guard value.isFinite else { return DisplayValue(number: placeholder, unit: fullUnit) }
        var scaled = roundTo(value / prefix.factor, decimals: decimals)
        if scaled == 0 { scaled = 0 } // turns -0.0 into 0.0 so the display never shows "-0.000"
        return DisplayValue(number: String(format: "%.\(decimals)f", scaled), unit: fullUnit)
    }

    /// Number of digits in front of the decimal point (at least 1).
    private static func integerDigits(_ magnitude: Double) -> Int {
        guard magnitude.isFinite, magnitude >= 1 else { return 1 }
        var count = 1
        var limit = 10.0
        while magnitude >= limit * (1 - 1e-9), count < 12 {
            count += 1
            limit *= 10
        }
        return count
    }

    private static func roundTo(_ value: Double, decimals: Int) -> Double {
        let scale = pow(10.0, Double(decimals))
        return (value * scale).rounded() / scale
    }
}
