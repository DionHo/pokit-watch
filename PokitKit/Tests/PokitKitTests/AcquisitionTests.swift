import XCTest
@testable import PokitKit

/// Byte vectors marked "dokit" are from the unit tests of the dokit project, which captured
/// them from real devices.
final class AcquisitionTests: XCTestCase {
    private func bytes(_ values: [UInt8]) -> Data { Data(values) }

    // MARK: Samples

    func testSamplesAreSignedLittleEndian() {
        // dokit "endianness"
        XCTAssertEqual(SampleDecoder.samples(from: bytes([0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0xFF, 0xFF])), [0, -256, 255, -1])
        // dokit "PokitPro" (oscilloscope)
        let capture = bytes([
            0xDA, 0x36, 0x91, 0x24, 0x24, 0x09, 0x02, 0x80, 0x91, 0x64,
            0x48, 0x12, 0x23, 0x49, 0x01, 0xC0, 0x4A, 0x92, 0xDC, 0xF6,
        ])
        XCTAssertEqual(
            SampleDecoder.samples(from: capture),
            [14042, 9361, 2340, -32766, 25745, 4680, 18723, -16383, -28086, -2340]
        )
        // dokit "PokitPro" (data logger)
        XCTAssertEqual(
            SampleDecoder.samples(from: bytes([0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F])),
            [32767, 32767, 32767, 32767, 32767]
        )
    }

    func testEmptyAndOddSampleData() {
        XCTAssertEqual(SampleDecoder.samples(from: Data()), [])
        XCTAssertNil(SampleDecoder.samples(from: bytes([0xFF, 0xFF, 0xFF])))
    }

    func testSamplesFromADataSlice() {
        let whole = bytes([0xAA, 0x01, 0x00, 0x02, 0x00])
        XCTAssertEqual(SampleDecoder.samples(from: whole.dropFirst()), [1, 2])
    }

    // MARK: Oscilloscope

    func testScopeSettingsEncoding() {
        // dokit "AcVoltage": rising edge at 1.0, AC voltage, range 4, 1 s window, 1000 samples
        let settings = ScopeSettings(
            trigger: .risingEdge(level: 1.0), mode: .acVoltage, rangeIndex: 4, window: 1_000_000, sampleCount: 1000
        )
        XCTAssertEqual(
            settings.encoded(),
            bytes([0x01, 0x00, 0x00, 0x80, 0x3F, 0x02, 0x04, 0x40, 0x42, 0x0F, 0x00, 0xE8, 0x03])
        )
        // dokit "zeroed"
        XCTAssertEqual(ScopeSettings.idle.encoded(), Data(count: 13))
    }

    func testScopeTriggerCommands() {
        func command(_ trigger: ScopeTrigger) -> UInt8 {
            ScopeSettings(trigger: trigger, mode: .dcVoltage, rangeIndex: 0, window: 1000, sampleCount: 10).encoded()[0]
        }
        XCTAssertEqual(command(.freeRunning), 0)
        XCTAssertEqual(command(.risingEdge(level: 0)), 1)
        XCTAssertEqual(command(.fallingEdge(level: -2.5)), 2)

        let falling = ScopeSettings(trigger: .fallingEdge(level: -2.5), mode: .dcVoltage, rangeIndex: 0, window: 1000, sampleCount: 10)
        XCTAssertEqual(Array(falling.encoded()[1...4]), [0x00, 0x00, 0x20, 0xC0])
    }

    func testScopeMetadataFromPokitMeter() throws {
        // dokit "PokitMeter"
        let metadata = try XCTUnwrap(ScopeMetadata(data: bytes([
            0x00, 0x98, 0xF7, 0x8B, 0x33, 0x02, 0x00, 0x40, 0x42, 0x0F, 0x00, 0x0A, 0x00, 0x0A, 0x00, 0x00, 0x00,
        ])))
        XCTAssertEqual(metadata.status, .done)
        XCTAssertEqual(metadata.scale, 6.517728934e-08, accuracy: 1e-14)
        XCTAssertEqual(metadata.modeByte, MultimeterMode.acVoltage.rawValue)
        XCTAssertEqual(metadata.rangeIndex, 0)
        XCTAssertEqual(metadata.window, 1_000_000)
        XCTAssertEqual(metadata.sampleCount, 10)
        XCTAssertEqual(metadata.samplingRate, 10)
    }

    func testScopeMetadataFromPokitProHasExtraBytes() throws {
        // dokit "PokitPro": 21 bytes, the last four are not documented
        let metadata = try XCTUnwrap(ScopeMetadata(data: bytes([
            0x00, 0xCC, 0xEC, 0xBA, 0x33, 0x02, 0x00, 0x40, 0x42, 0x0F, 0x00,
            0xE8, 0x03, 0x0A, 0x00, 0x00, 0x00, 0x14, 0x00, 0x00, 0x00,
        ])))
        XCTAssertEqual(metadata.status, .done)
        XCTAssertEqual(metadata.scale, 8.704373045e-08, accuracy: 1e-14)
        XCTAssertEqual(metadata.window, 1_000_000)
        XCTAssertEqual(metadata.sampleCount, 1000)
        XCTAssertEqual(metadata.samplingRate, 10)
    }

    func testShortScopeMetadataIsRejected() {
        XCTAssertNil(ScopeMetadata(data: Data()))
        XCTAssertNil(ScopeMetadata(data: Data(repeating: 0xFF, count: 16)))
    }

    func testAcquisitionStatusBytes() {
        XCTAssertEqual(AcquisitionStatus(byte: 0), .done)
        XCTAssertEqual(AcquisitionStatus(byte: 1), .sampling)
        XCTAssertEqual(AcquisitionStatus(byte: 2), .bufferFull)
        XCTAssertEqual(AcquisitionStatus(byte: 255), .error)
        XCTAssertEqual(AcquisitionStatus(byte: 7), .unknown(7))
    }

    // MARK: Range advice

    func testRangeAdvisorStepsUpAsFarAsNeeded() {
        let ranges = PokitProduct.meter.ranges(for: .dcVoltage) // 0.3, 2, 6, 12, 30, 60
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 0, peak: 5.0, ranges: ranges), 2)
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 0, peak: 0.29, ranges: ranges), 1)
        // Beyond everything: the highest range is all there is.
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 4, peak: 80, ranges: ranges), 5)
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 5, peak: 80, ranges: ranges), 5)
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 2, peak: .infinity, ranges: ranges), 5)
    }

    func testRangeAdvisorStepsDownOneAtATimeAndIsStable() {
        let ranges = PokitProduct.meter.ranges(for: .dcVoltage)
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 5, peak: 0.1, ranges: ranges), 4)
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 2, peak: 1.0, ranges: ranges), 1)
        // Fits where it is.
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 2, peak: 5.0, ranges: ranges), 2)
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 0, peak: 0.01, ranges: ranges), 0)
        // 1.5 V would fit the 2 V range, but not with enough margin to leave the 6 V range;
        // and once in the 2 V range it must not be sent back up.
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 2, peak: 1.5, ranges: ranges), 2)
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 1, peak: 1.5, ranges: ranges), 1)
    }

    func testRangeAdvisorWithUnknownRange() {
        let ranges = PokitProduct.pro.ranges(for: .dcCurrent)
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 200, peak: 0.001, ranges: ranges), 6)
        XCTAssertEqual(ScopeRangeAdvisor.nextRange(current: 3, peak: 1, ranges: []), 3)
    }

    // MARK: Data logger

    func testLoggerSettingsEncodingPro() {
        // dokit "AcVoltage": start, AC voltage, range 5, every 60 s, timestamp 0xD9B20B56
        let settings = LoggerSettings.start(mode: .acVoltage, rangeIndex: 5, interval: 60, timestamp: 0xD9B2_0B56)
        XCTAssertEqual(
            settings.encoded(layout: .pro),
            bytes([0x00, 0x00, 0x00, 0x02, 0x05, 0x60, 0xEA, 0x00, 0x00, 0x56, 0x0B, 0xB2, 0xD9])
        )
        // dokit "stop:pro", "refresh:pro"
        XCTAssertEqual(LoggerSettings.stop.encoded(layout: .pro), bytes([0x01] + [UInt8](repeating: 0, count: 12)))
        XCTAssertEqual(LoggerSettings.refresh.encoded(layout: .pro), bytes([0x02] + [UInt8](repeating: 0, count: 12)))
    }

    func testLoggerSettingsEncodingMeter() {
        // Same start as above in the Meter's layout: 16-bit seconds.
        let settings = LoggerSettings.start(mode: .acVoltage, rangeIndex: 5, interval: 60, timestamp: 0xD9B2_0B56)
        XCTAssertEqual(
            settings.encoded(layout: .meter),
            bytes([0x00, 0x00, 0x00, 0x02, 0x05, 0x3C, 0x00, 0x56, 0x0B, 0xB2, 0xD9])
        )
        // dokit "stop:meter", "refresh:meter"
        XCTAssertEqual(LoggerSettings.stop.encoded(layout: .meter), bytes([0x01] + [UInt8](repeating: 0, count: 10)))
        XCTAssertEqual(LoggerSettings.refresh.encoded(layout: .meter), bytes([0x02] + [UInt8](repeating: 0, count: 10)))
    }

    func testLoggerIntervalDoesNotOverflow() {
        let long = LoggerSettings.start(mode: .dcVoltage, rangeIndex: 0, interval: 100_000, timestamp: 0)
        XCTAssertEqual(Array(long.encoded(layout: .meter)[5...6]), [0xFF, 0xFF])
        let huge = LoggerSettings.start(mode: .dcVoltage, rangeIndex: 0, interval: .max, timestamp: 0)
        XCTAssertEqual(Array(huge.encoded(layout: .pro)[5...8]), [0xFF, 0xFF, 0xFF, 0xFF])
    }

    func testLoggerMetadataFromPokitMeter() throws {
        // dokit "PokitMeter": 15 bytes, interval 60 s, no samples
        let metadata = try XCTUnwrap(LoggerMetadata(data: bytes([
            0x00, 0x9F, 0x0F, 0x49, 0x37, 0x00, 0x04, 0x3C, 0x00, 0x00, 0x00, 0xE9, 0xBB, 0x8C, 0x62,
        ])))
        XCTAssertEqual(metadata.layout, .meter)
        XCTAssertEqual(metadata.status, .done)
        XCTAssertEqual(metadata.scale, 1.198417067e-05, accuracy: 1e-12)
        XCTAssertEqual(metadata.modeByte, 0)
        XCTAssertNil(metadata.mode)
        XCTAssertEqual(metadata.rangeIndex, 4)
        XCTAssertEqual(metadata.interval, 60)
        XCTAssertEqual(metadata.sampleCount, 0)
        XCTAssertEqual(metadata.timestamp, 1_653_390_313)
        XCTAssertEqual(metadata.startDate, Date(timeIntervalSince1970: 1_653_390_313))
    }

    func testLoggerMetadataFromPokitPro() throws {
        // dokit "PokitPro": 23 bytes, interval 60000 ms, 13 samples
        let metadata = try XCTUnwrap(LoggerMetadata(data: bytes([
            0x00, 0x39, 0xF0, 0x45, 0x3C, 0x00, 0x04, 0x60, 0xEA, 0x00, 0x00, 0x0D,
            0x00, 0x00, 0x00, 0x30, 0x38, 0x00, 0x00, 0x43, 0xB9, 0x8C, 0x62,
        ])))
        XCTAssertEqual(metadata.layout, .pro)
        XCTAssertEqual(metadata.status, .done)
        XCTAssertEqual(metadata.scale, 0.01208119933, accuracy: 1e-9)
        XCTAssertEqual(metadata.rangeIndex, 4)
        XCTAssertEqual(metadata.interval, 60)
        XCTAssertEqual(metadata.sampleCount, 13)
        XCTAssertEqual(metadata.timestamp, 1_653_389_635)
    }

    func testShortLoggerMetadataIsRejected() {
        XCTAssertNil(LoggerMetadata(data: Data()))
        XCTAssertNil(LoggerMetadata(data: Data(repeating: 0xFF, count: 14)))
    }

    func testLoggerStartDateIgnoresForeignTimestamps() throws {
        var raw = [UInt8](repeating: 0, count: 15)
        raw[11] = 0x10 // a small number, not a date
        XCTAssertNil(try XCTUnwrap(LoggerMetadata(data: Data(raw))).startDate)
    }

    func testLoggerModesMapToMultimeterModes() {
        XCTAssertEqual(LoggerMode.temperature.rawValue, 5)
        XCTAssertEqual(LoggerMode.temperature.multimeterMode, .temperature)
        XCTAssertEqual(LoggerMode.dcCurrent.multimeterMode, .dcCurrent)
        XCTAssertEqual(LoggerLayout(product: .meter), .meter)
        XCTAssertEqual(LoggerLayout(product: .pro), .pro)
    }

    // MARK: Waveform summary

    func testSummaryOfASineWave() throws {
        // 50 Hz, 2 V amplitude around 1 V, sampled at 5 kHz for 100 ms.
        let rate = 5000.0
        let samples = (0..<500).map { 1 + 2 * sin(2 * Double.pi * 50 * Double($0) / rate) }
        let summary = try XCTUnwrap(WaveformSummary(samples: samples, sampleRate: rate))
        XCTAssertEqual(summary.minimum, -1, accuracy: 0.01)
        XCTAssertEqual(summary.maximum, 3, accuracy: 0.01)
        XCTAssertEqual(summary.peakToPeak, 4, accuracy: 0.02)
        XCTAssertEqual(summary.mean, 1, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(summary.frequency), 50, accuracy: 0.2)
    }

    func testSummaryOfASquareWaveWithNoise() throws {
        // 1 kHz square wave, 0/5 V, sampled at 100 kHz, with a little ripple on the levels.
        let rate = 100_000.0
        let samples = (0..<1000).map { index -> Double in
            let high = (index / 50) % 2 == 0
            return (high ? 5.0 : 0.0) + 0.05 * sin(Double(index))
        }
        let summary = try XCTUnwrap(WaveformSummary(samples: samples, sampleRate: rate))
        XCTAssertEqual(try XCTUnwrap(summary.frequency), 1000, accuracy: 5)
    }

    func testSummaryWithoutAFrequency() throws {
        // Flat.
        XCTAssertNil(try XCTUnwrap(WaveformSummary(samples: [Double](repeating: 3.3, count: 100), sampleRate: 1000)).frequency)
        // A single edge is not a period.
        let step = [Double](repeating: 0, count: 50) + [Double](repeating: 5, count: 50)
        XCTAssertNil(try XCTUnwrap(WaveformSummary(samples: step, sampleRate: 1000)).frequency)
        // No sample rate given (a log).
        let ramp = (0..<100).map { sin(Double($0) / 3) }
        XCTAssertNil(try XCTUnwrap(WaveformSummary(samples: ramp)).frequency)
    }

    func testSummaryIgnoresNonFiniteSamplesAndNeedsData() throws {
        XCTAssertNil(WaveformSummary(samples: []))
        XCTAssertNil(WaveformSummary(samples: [.nan, .infinity]))
        let summary = try XCTUnwrap(WaveformSummary(samples: [1, .nan, 3]))
        XCTAssertEqual(summary.minimum, 1)
        XCTAssertEqual(summary.maximum, 3)
        XCTAssertEqual(summary.mean, 2)
    }
}
