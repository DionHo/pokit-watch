import XCTest
@testable import PokitKit

final class ValueFormatterTests: XCTestCase {
    func testFixedRangeKeepsDecimalPointStable() {
        // 300 mV range: everything is shown in mV with one decimal.
        XCTAssertEqual(ValueFormatter.format(0.01234, unit: "V", fullScale: 0.3), DisplayValue(number: "12.3", unit: "mV"))
        XCTAssertEqual(ValueFormatter.format(0.25, unit: "V", fullScale: 0.3), DisplayValue(number: "250.0", unit: "mV"))
        XCTAssertEqual(ValueFormatter.format(0, unit: "V", fullScale: 0.3), DisplayValue(number: "0.0", unit: "mV"))
        // 6 V range: volts with three decimals.
        XCTAssertEqual(ValueFormatter.format(1.5, unit: "V", fullScale: 6), DisplayValue(number: "1.500", unit: "V"))
        XCTAssertEqual(ValueFormatter.format(-5.4321, unit: "V", fullScale: 6), DisplayValue(number: "-5.432", unit: "V"))
        // 60 V range: two decimals.
        XCTAssertEqual(ValueFormatter.format(48.123, unit: "V", fullScale: 60), DisplayValue(number: "48.12", unit: "V"))
    }

    func testFixedRangeResistanceAndCurrent() {
        XCTAssertEqual(ValueFormatter.format(1234, unit: "Ω", fullScale: 1500), DisplayValue(number: "1.234", unit: "kΩ"))
        XCTAssertEqual(ValueFormatter.format(470_000, unit: "Ω", fullScale: 470_000), DisplayValue(number: "470.0", unit: "kΩ"))
        XCTAssertEqual(ValueFormatter.format(999_500, unit: "Ω", fullScale: 1_000_000), DisplayValue(number: "1.000", unit: "MΩ"))
        XCTAssertEqual(ValueFormatter.format(0.0042, unit: "A", fullScale: 0.01), DisplayValue(number: "4.20", unit: "mA"))
        XCTAssertEqual(ValueFormatter.format(0.00025, unit: "A", fullScale: 0.0005), DisplayValue(number: "250.0", unit: "µA"))
    }

    func testNegativeZeroIsShownWithoutSign() {
        XCTAssertEqual(ValueFormatter.format(-0.00001, unit: "V", fullScale: 6).number, "0.000")
        XCTAssertEqual(ValueFormatter.format(-0.0, unit: "V", fullScale: 6).number, "0.000")
    }

    func testAutoPrefix() {
        XCTAssertEqual(ValueFormatter.format(0.000_000_1, unit: "F"), DisplayValue(number: "100.0", unit: "nF"))
        XCTAssertEqual(ValueFormatter.format(4.7e-6, unit: "F"), DisplayValue(number: "4.700", unit: "µF"))
        XCTAssertEqual(ValueFormatter.format(12.5, unit: "V"), DisplayValue(number: "12.50", unit: "V"))
        XCTAssertEqual(ValueFormatter.format(2_200_000, unit: "Ω"), DisplayValue(number: "2.200", unit: "MΩ"))
        XCTAssertEqual(ValueFormatter.format(0, unit: "V"), DisplayValue(number: "0.000", unit: "V"))
    }

    func testAutoPrefixRoundingCarriesIntoNextPrefix() {
        XCTAssertEqual(ValueFormatter.format(999.96, unit: "Ω"), DisplayValue(number: "1.000", unit: "kΩ"))
        XCTAssertEqual(ValueFormatter.format(0.99996, unit: "V"), DisplayValue(number: "1.000", unit: "V"))
    }

    func testAutoPrefixRespectsLimits() {
        // Noise around zero must not drop into µV when the smallest allowed prefix is milli.
        XCTAssertEqual(ValueFormatter.format(0.000_012, unit: "V", minimum: .milli), DisplayValue(number: "0.012", unit: "mV"))
        XCTAssertEqual(ValueFormatter.format(5_000_000_000, unit: "Ω", maximum: .mega).unit, "MΩ")
    }

    func testNonFiniteValuesUsePlaceholder() {
        XCTAssertEqual(ValueFormatter.format(.infinity, unit: "Ω").number, ValueFormatter.placeholder)
        XCTAssertEqual(ValueFormatter.format(.nan, unit: "V", fullScale: 6), DisplayValue(number: ValueFormatter.placeholder, unit: "V"))
    }

    func testPlainFormatting() {
        XCTAssertEqual(ValueFormatter.formatPlain(23.456, unit: "°C", decimals: 1), DisplayValue(number: "23.5", unit: "°C"))
        XCTAssertEqual(ValueFormatter.formatPlain(-3.04, unit: "°C", decimals: 1).text, "-3.0 °C")
    }
}
