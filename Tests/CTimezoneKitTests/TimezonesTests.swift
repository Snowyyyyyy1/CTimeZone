@testable import CTimezoneKit
import XCTest

final class TimezonesTests: XCTestCase {
    func testKnownZoneValid() {
        XCTAssertTrue(Timezones.isValid("Europe/Amsterdam"))
        XCTAssertTrue(Timezones.isValid("Asia/Shanghai"))
    }

    func testFixedOffsetZoneValidDespiteNotInKnownList() {
        // `UTC` resolves but is not in `knownTimeZoneIdentifiers`.
        XCTAssertTrue(Timezones.isValid("UTC"))
        XCTAssertFalse(TimeZone.knownTimeZoneIdentifiers.contains("UTC"))
    }

    func testInvalidAndEmptyRejected() {
        XCTAssertFalse(Timezones.isValid("Not/AZone"))
        XCTAssertFalse(Timezones.isValid(""))
        XCTAssertFalse(Timezones.isValid("foo bar"))
    }

    func testCatalogContainsUTCAndIsSorted() {
        let catalog = Timezones.catalog()
        XCTAssertTrue(catalog.contains("UTC"))
        XCTAssertTrue(catalog.contains("Europe/Amsterdam"))
        XCTAssertEqual(catalog, catalog.sorted())
    }
}
