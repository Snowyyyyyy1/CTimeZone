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

    func testCityNamesFollowTheLocale() {
        let zones = ["America/New_York", "Asia/Shanghai", "UTC"]
        let chinese = Timezones.cityNames(for: zones, locale: Locale(identifier: "zh-Hans"))
        XCTAssertEqual(chinese["America/New_York"], "纽约")
        XCTAssertEqual(chinese["Asia/Shanghai"], "上海")
        XCTAssertEqual(chinese["UTC"], "UTC")
        let english = Timezones.cityNames(for: zones, locale: Locale(identifier: "en"))
        XCTAssertEqual(english["America/New_York"], "New York")
    }
}
