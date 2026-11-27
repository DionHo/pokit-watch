import XCTest
@testable import PokitKit

final class QuickStartLinkTests: XCTestCase {
    func testEveryMeasurementModeSurvivesTheRoundTrip() throws {
        for mode in MultimeterMode.allCases where mode != .idle {
            let url = try XCTUnwrap(QuickStartLink.url(for: mode))
            XCTAssertEqual(QuickStartLink.mode(from: url), mode)
        }
    }

    func testLinkFormat() {
        XCTAssertEqual(QuickStartLink.url(for: .dcVoltage)?.absoluteString, "wristmeter://mode/1")
    }

    func testOtherURLsAreNotQuickStarts() throws {
        // Idle is a valid mode byte but not something to start in.
        XCTAssertNil(QuickStartLink.mode(from: try XCTUnwrap(URL(string: "wristmeter://mode/0"))))
        XCTAssertNil(QuickStartLink.mode(from: try XCTUnwrap(URL(string: "wristmeter://mode/99"))))
        XCTAssertNil(QuickStartLink.mode(from: try XCTUnwrap(URL(string: "wristmeter://mode/"))))
        XCTAssertNil(QuickStartLink.mode(from: try XCTUnwrap(URL(string: "wristmeter://mode/1/extra"))))
        XCTAssertNil(QuickStartLink.mode(from: try XCTUnwrap(URL(string: "wristmeter://open"))))
        XCTAssertNil(QuickStartLink.mode(from: try XCTUnwrap(URL(string: "https://example.com/mode/1"))))
    }
}
