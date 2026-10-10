@testable import CTimezoneKit
import XCTest

final class DesktopModePreferenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "ctz-mode-\(UUID().uuidString)"

    override func setUpWithError() throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testUnsetPreferenceWithConfiguredAmsterdamSeedsFixed() {
        XCTAssertNil(defaults.object(forKey: DesktopModePreference.key))
        let mode = DesktopModePreference.load(defaults, configuredTZ: "Europe/Amsterdam")
        XCTAssertEqual(mode, .fixed("Europe/Amsterdam"))
    }

    func testUnsetPreferenceWithNoConfigSeedsSystem() {
        let mode = DesktopModePreference.load(defaults, configuredTZ: nil)
        XCTAssertEqual(mode, .system)
    }

    func testUnsetPreferenceWithInvalidConfigSeedsSystem() {
        let mode = DesktopModePreference.load(defaults, configuredTZ: "Not/AZone")
        XCTAssertEqual(mode, .system)
    }

    func testExplicitSystemPersistsAcrossReload() {
        DesktopModePreference.store(.system, in: defaults)
        // Even with an Amsterdam config present, an explicit System choice wins.
        let mode = DesktopModePreference.load(defaults, configuredTZ: "Europe/Amsterdam")
        XCTAssertEqual(mode, .system)
    }

    func testExplicitFixedPersists() {
        DesktopModePreference.store(.fixed("Asia/Tokyo"), in: defaults)
        let mode = DesktopModePreference.load(defaults, configuredTZ: "Europe/Amsterdam")
        XCTAssertEqual(mode, .fixed("Asia/Tokyo"))
    }

    func testAbsenceIsNotTreatedAsExplicitSystem() {
        // Absence + configured value must seed fixed, not system.
        XCTAssertNil(defaults.object(forKey: DesktopModePreference.key))
        XCTAssertEqual(
            DesktopModePreference.load(defaults, configuredTZ: "Europe/Amsterdam"),
            .fixed("Europe/Amsterdam")
        )
    }
}
