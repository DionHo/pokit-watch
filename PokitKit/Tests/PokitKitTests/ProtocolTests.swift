import XCTest
@testable import PokitKit

/// The byte vectors are captures from real devices, taken from dokit's unit tests.
final class ProtocolTests: XCTestCase {
    private func data(_ hex: String) -> Data {
        Data(hex.split(separator: " ").map { UInt8($0, radix: 16)! })
    }

    // MARK: Settings

    func testSettingsEncoding() {
        let acVolts = MultimeterSettings(mode: .acVoltage, range: .fixed(2), updateInterval: 1000)
        XCTAssertEqual(acVolts.encoded(), data("02 02 E8 03 00 00"))

        let diode = MultimeterSettings(mode: .diode, range: .auto, updateInterval: 5000)
        XCTAssertEqual(diode.encoded(), data("06 FF 88 13 00 00"))

        let resistance = MultimeterSettings(mode: .resistance, range: .auto, updateInterval: 60000)
        XCTAssertEqual(resistance.encoded(), data("05 FF 60 EA 00 00"))
    }

    func testSettingsIgnoreRangeForModesWithoutRanges() {
        let continuity = MultimeterSettings(mode: .continuity, range: .fixed(3), updateInterval: 100)
        XCTAssertEqual(continuity.encoded(), data("07 FF 64 00 00 00"))
        XCTAssertEqual(MultimeterSettings.idle.encoded().first, 0)
        XCTAssertEqual(MultimeterSettings.idle.encoded().count, 6)
    }

    func testRangeSelectionBytes() {
        XCTAssertEqual(RangeSelection.auto.byte, 0xFF)
        XCTAssertEqual(RangeSelection.fixed(4).byte, 4)
        XCTAssertEqual(RangeSelection(byte: 0xFF), .auto)
        XCTAssertEqual(RangeSelection(byte: 1), .fixed(1))
    }

    // MARK: Reading

    func testReadingDecodingMeter() throws {
        let reading = try XCTUnwrap(MultimeterReading(data: data("00 00 00 00 00 01 03")))
        XCTAssertEqual(reading.statusByte, 0)
        XCTAssertEqual(reading.value, 0)
        XCTAssertEqual(reading.mode, .dcVoltage)
        XCTAssertEqual(reading.rangeIndex, 3)
        XCTAssertEqual(reading.isAutoRange, false)
        XCTAssertNil(reading.hasContinuity)
        XCTAssertFalse(reading.isError)
        XCTAssertFalse(reading.isOverload)
    }

    func testReadingDecodingPro() throws {
        let reading = try XCTUnwrap(MultimeterReading(data: data("00 94 89 FA 3B 02 00")))
        XCTAssertEqual(reading.value, 0.007645795, accuracy: 1e-8)
        XCTAssertEqual(reading.mode, .acVoltage)
        XCTAssertEqual(reading.rangeIndex, 0)
    }

    func testReadingAcceptsLongerAndRejectsShorterValues() {
        XCTAssertNotNil(MultimeterReading(data: data("01 00 00 80 3F 05 02 AA BB CC")))
        XCTAssertNil(MultimeterReading(data: data("01 00 00 80 3F 05")))
        XCTAssertNil(MultimeterReading(data: Data()))
    }

    func testReadingDecodingWorksOnDataSlices() throws {
        // A slice keeps the indices of its parent; decoding must not assume it starts at 0.
        let parent = data("EE EE 01 00 00 80 3F 05 02")
        let reading = try XCTUnwrap(MultimeterReading(data: parent.dropFirst(2)))
        XCTAssertEqual(reading.value, 1.0)
        XCTAssertEqual(reading.mode, .resistance)
        XCTAssertEqual(reading.rangeIndex, 2)
        XCTAssertEqual(reading.isAutoRange, true)
    }

    func testReadingStatusInterpretation() throws {
        let continuity = try XCTUnwrap(MultimeterReading(data: data("01 00 00 00 40 07 00")))
        XCTAssertEqual(continuity.hasContinuity, true)
        XCTAssertNil(continuity.isAutoRange)

        let open = try XCTUnwrap(MultimeterReading(data: data("00 00 00 80 7F 07 00"))) // +infinity
        XCTAssertEqual(open.hasContinuity, false)
        XCTAssertTrue(open.isOverload)

        let error = try XCTUnwrap(MultimeterReading(data: data("FF 00 00 00 00 03 00")))
        XCTAssertTrue(error.isError)
        XCTAssertNil(error.isAutoRange)

        let unknownMode = try XCTUnwrap(MultimeterReading(data: data("00 00 00 00 00 2A 00")))
        XCTAssertNil(unknownMode.mode)
    }

    // MARK: Status service

    func testDeviceCharacteristicsMeter() throws {
        let value = try XCTUnwrap(DeviceCharacteristics(
            data: data("01 04 3C 00 02 00 E8 03 E8 03 00 20 00 00 84 2E 14 2C 03 A8")))
        XCTAssertEqual(value.firmwareVersion, "1.4")
        XCTAssertEqual(value.maximumVoltage, 60)
        XCTAssertEqual(value.maximumCurrent, 2)
        XCTAssertEqual(value.maximumResistance, 1000)
        XCTAssertEqual(value.maximumSamplingRate, 1000)
        XCTAssertEqual(value.samplingBufferSize, 8192)
        XCTAssertEqual(value.capabilityMask, 0)
        XCTAssertEqual(value.macAddress, "84:2E:14:2C:03:A8")
    }

    func testDeviceCharacteristicsPro() throws {
        let value = try XCTUnwrap(DeviceCharacteristics(
            data: data("01 03 52 03 0A 00 B8 0B E8 03 00 40 00 00 5C 02 72 09 AA 25")))
        XCTAssertEqual(value.firmwareVersion, "1.3")
        XCTAssertEqual(value.maximumVoltage, 850)
        XCTAssertEqual(value.maximumCurrent, 10)
        XCTAssertEqual(value.maximumResistance, 3000)
        XCTAssertEqual(value.samplingBufferSize, 16384)
        XCTAssertEqual(value.macAddress, "5C:02:72:09:AA:25")
        XCTAssertNil(DeviceCharacteristics(data: data("01 03 52 03")))
    }

    func testStatusMeterHasNoProFields() throws {
        let status = try XCTUnwrap(DeviceStatus(data: data("00 25 07 33 40")))
        XCTAssertEqual(status.activityByte, 0)
        XCTAssertEqual(status.batteryVoltage, 2.797, accuracy: 0.001)
        XCTAssertNil(status.batteryStatus)
        XCTAssertNil(status.switchPosition)
        XCTAssertNil(status.chargingStatus)
        XCTAssertEqual(status.estimatedBatteryLevel(for: .meter), 0.746, accuracy: 0.01)
    }

    func testStatusPro() throws {
        let status = try XCTUnwrap(DeviceStatus(data: data("02 64 3B 83 40 01 00 00")))
        XCTAssertEqual(status.activityByte, 2)
        XCTAssertEqual(status.batteryVoltage, 4.101, accuracy: 0.001)
        XCTAssertEqual(status.batteryStatus, .good)
        XCTAssertEqual(status.switchPosition, .voltage)
        XCTAssertEqual(status.chargingStatus, .discharging)

        let charging = try XCTUnwrap(DeviceStatus(data: data("00 E5 D0 82 40 01 01 01")))
        XCTAssertEqual(charging.switchPosition, .multiMode)
        XCTAssertEqual(charging.chargingStatus, .charging)
        XCTAssertEqual(charging.estimatedBatteryLevel(for: .pro), 0.917, accuracy: 0.01)

        XCTAssertNil(DeviceStatus(data: data("00 25 07 33")))
    }

    func testButtonEvent() {
        XCTAssertEqual(ButtonEvent(data: data("02 00")), .released)
        XCTAssertEqual(ButtonEvent(data: data("02 01")), .pressed)
        XCTAssertEqual(ButtonEvent(data: data("02 02")), .held)
        XCTAssertNil(ButtonEvent(data: data("02")))
        XCTAssertNil(ButtonEvent(data: data("02 09")))
    }

    func testTextDecodingStripsTrailingNul() {
        XCTAssertEqual(PokitText.decode(Data("PokitPro".utf8) + Data([0])), "PokitPro")
        XCTAssertEqual(PokitText.decode(Data("1.04".utf8)), "1.04")
        XCTAssertNil(PokitText.decode(Data([0, 0])))
        XCTAssertNil(PokitText.decode(Data()))
    }

    // MARK: Products and ranges

    func testProductDetection() {
        XCTAssertEqual(PokitProduct(statusServiceUUID: "57d3a771-267c-4394-8872-78223e92aec4"), .meter)
        XCTAssertEqual(PokitProduct(statusServiceUUID: "57D3A771-267C-4394-8872-78223E92AEC5"), .pro)
        XCTAssertNil(PokitProduct(statusServiceUUID: PokitUUID.multimeterService))
    }

    func testRangeTables() {
        XCTAssertEqual(PokitProduct.meter.ranges(for: .dcVoltage).map(\.fullScale), [0.3, 2, 6, 12, 30, 60])
        XCTAssertEqual(PokitProduct.meter.ranges(for: .acCurrent).count, 5)
        XCTAssertEqual(PokitProduct.meter.ranges(for: .resistance).last?.fullScale, 1_000_000)
        XCTAssertTrue(PokitProduct.meter.ranges(for: .capacitance).isEmpty)
        XCTAssertEqual(PokitProduct.pro.ranges(for: .acVoltage).last, MeterRange(index: 7, fullScale: 600))
        XCTAssertEqual(PokitProduct.pro.ranges(for: .resistance).count, 11)
        XCTAssertEqual(PokitProduct.pro.ranges(for: .capacitance).count, 3)
        XCTAssertTrue(PokitProduct.pro.ranges(for: .continuity).isEmpty)
        XCTAssertEqual(PokitProduct.meter.range(for: .dcVoltage, index: 3)?.fullScale, 12)
        XCTAssertNil(PokitProduct.meter.range(for: .dcVoltage, index: 6))
        XCTAssertNil(PokitProduct.meter.range(for: .dcVoltage, index: 255))
    }

    func testRangeLabels() {
        XCTAssertEqual(PokitProduct.meter.ranges(for: .dcVoltage).map { $0.label(unit: "V") },
                       ["300 mV", "2 V", "6 V", "12 V", "30 V", "60 V"])
        XCTAssertEqual(PokitProduct.meter.ranges(for: .resistance).map { $0.label(unit: "Ω") },
                       ["160 Ω", "330 Ω", "890 Ω", "1.5 kΩ", "10 kΩ", "100 kΩ", "470 kΩ", "1 MΩ"])
        XCTAssertEqual(PokitProduct.pro.ranges(for: .dcCurrent).map { $0.label(unit: "A") },
                       ["500 µA", "2 mA", "10 mA", "125 mA", "300 mA", "3 A", "10 A"])
        XCTAssertEqual(PokitProduct.pro.ranges(for: .capacitance).map { $0.label(unit: "F") },
                       ["100 nF", "10 µF", "1 mF"])
    }

    func testEveryMeasurementModeIsKnownAndNotIdle() {
        for product in PokitProduct.allCases {
            XCTAssertFalse(product.measurementModes.contains(.idle))
            XCTAssertEqual(Set(product.measurementModes).count, product.measurementModes.count)
        }
        XCTAssertFalse(PokitProduct.meter.measurementModes.contains(.capacitance))
    }

    func testSwitchPositionHints() {
        XCTAssertTrue(SwitchPosition.voltage.isExpectedToSupport(.dcVoltage))
        XCTAssertFalse(SwitchPosition.voltage.isExpectedToSupport(.resistance))
        XCTAssertTrue(SwitchPosition.multiMode.isExpectedToSupport(.continuity))
        XCTAssertFalse(SwitchPosition.multiMode.isExpectedToSupport(.acVoltage))
        XCTAssertTrue(SwitchPosition.highCurrent.isExpectedToSupport(.dcCurrent))
        XCTAssertFalse(SwitchPosition.highCurrent.isExpectedToSupport(.capacitance))
        XCTAssertTrue(SwitchPosition.highCurrent.isExpectedToSupport(.temperature))
    }

    // MARK: Display

    func testDisplayUsesTheReportedRange() {
        let reading = MultimeterReading(statusByte: 1, value: 4.9871, modeByte: 1, rangeIndex: 2)
        let display = MeterDisplay(reading: reading, product: .meter)
        XCTAssertEqual(display.value, DisplayValue(number: "4.987", unit: "V"))
        XCTAssertEqual(display.rangeLabel, "6 V")
        XCTAssertEqual(display.isAutoRange, true)
        XCTAssertEqual(display.condition, .normal)

        // The same reading means a different range on the Pro (index 2 = 10 V).
        XCTAssertEqual(MeterDisplay(reading: reading, product: .pro).value, DisplayValue(number: "4.99", unit: "V"))
    }

    func testDisplayMillivoltRange() {
        let reading = MultimeterReading(statusByte: 0, value: 0.007645795, modeByte: 2, rangeIndex: 0)
        XCTAssertEqual(MeterDisplay(reading: reading, product: .pro).value, DisplayValue(number: "7.6", unit: "mV"))
    }

    func testDisplayOverloadAndError() {
        let overload = MultimeterReading(statusByte: 0, value: .infinity, modeByte: 5, rangeIndex: 7)
        let overloadDisplay = MeterDisplay(reading: overload, product: .meter)
        XCTAssertEqual(overloadDisplay.condition, .overload)
        XCTAssertEqual(overloadDisplay.value, DisplayValue(number: "OL", unit: "Ω"))

        let error = MultimeterReading(statusByte: 255, value: 0, modeByte: 3, rangeIndex: 0)
        let errorDisplay = MeterDisplay(reading: error, product: .meter)
        XCTAssertEqual(errorDisplay.condition, .error)
        XCTAssertEqual(errorDisplay.value.number, "ERR")
    }

    func testDisplayModesWithoutRanges() {
        let temperature = MultimeterReading(statusByte: 0, value: 23.456, modeByte: 8, rangeIndex: 0)
        let temperatureDisplay = MeterDisplay(reading: temperature, product: .meter)
        XCTAssertEqual(temperatureDisplay.value, DisplayValue(number: "23.5", unit: "°C"))
        XCTAssertNil(temperatureDisplay.rangeLabel)
        XCTAssertNil(temperatureDisplay.isAutoRange)

        let diode = MultimeterReading(statusByte: 0, value: 0.6123, modeByte: 6, rangeIndex: 0)
        XCTAssertEqual(MeterDisplay(reading: diode, product: .meter).value, DisplayValue(number: "0.612", unit: "V"))

        let continuity = MultimeterReading(statusByte: 1, value: 12.3, modeByte: 7, rangeIndex: 0)
        let continuityDisplay = MeterDisplay(reading: continuity, product: .pro)
        XCTAssertEqual(continuityDisplay.hasContinuity, true)
        XCTAssertEqual(continuityDisplay.value, DisplayValue(number: "12.30", unit: "Ω"))
    }

    func testDisplayFallsBackToAutoPrefixForUnknownRange() {
        let reading = MultimeterReading(statusByte: 1, value: 0.0123, modeByte: 3, rangeIndex: 200)
        let display = MeterDisplay(reading: reading, product: .meter)
        XCTAssertEqual(display.value, DisplayValue(number: "12.30", unit: "mA"))
        XCTAssertNil(display.rangeLabel)
    }

    func testStatistics() {
        var stats = ReadingStatistics()
        XCTAssertNil(stats.minimum)
        [1.5, -2, 7, .infinity, .nan].forEach { stats.add($0) }
        XCTAssertEqual(stats.minimum, -2)
        XCTAssertEqual(stats.maximum, 7)
        XCTAssertEqual(stats.count, 3)
        stats.reset()
        XCTAssertEqual(stats, ReadingStatistics())
    }
}
