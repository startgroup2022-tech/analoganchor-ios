import XCTest
@testable import AnalogAnchorKit

final class OpenLocationCodeTests: XCTestCase {

    func testEncodeDecodeRoundTrip() throws {
        let code = try OpenLocationCode.encode(latitude: 26.2285, longitude: 50.5860)
        XCTAssertEqual(code.count, 11) // 10 digits + separator
        let area = try OpenLocationCode.decode(code)
        XCTAssertEqual(area.centerLatitude, 26.2285, accuracy: 0.001)
        XCTAssertEqual(area.centerLongitude, 50.5860, accuracy: 0.001)
    }

    func testKnownPlusCodeFromGoogleDocs() throws {
        // 27.175063, 78.042188 is the Taj Mahal; canonical Plus Code is 7JVW52GR+2V.
        let code = try OpenLocationCode.encode(latitude: 27.175063, longitude: 78.042188)
        XCTAssertTrue(code.hasPrefix("7JVW52GR"), "Unexpected code: \(code)")
    }

    func testValidatorRejectsBadCodes() {
        XCTAssertFalse(OpenLocationCode.isValidCode(""))
        XCTAssertFalse(OpenLocationCode.isValidCode("123"))
        XCTAssertTrue(OpenLocationCode.isValidCode("7JVW52GR+2V"))
    }

    func testParserHandlesRawCoordinates() throws {
        let parsed = LocationCodeParser.parse("26.2285, 50.5860")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.latitude, 26.2285, accuracy: 0.0001)
        XCTAssertEqual(parsed!.longitude, 50.5860, accuracy: 0.0001)
    }

    func testParserRecoversShortPlusCodeAgainstBahrain() throws {
        let parsed = LocationCodeParser.parse("6H7J+2XR")
        XCTAssertNotNil(parsed)
        // Should land near the Bahrain reference.
        XCTAssertEqual(parsed!.latitude, 26.2285, accuracy: 0.5)
        XCTAssertEqual(parsed!.longitude, 50.5860, accuracy: 0.5)
    }
}
