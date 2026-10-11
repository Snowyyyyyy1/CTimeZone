@testable import CTimezoneKit
import XCTest

final class AppLanguageTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "ctz-lang-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var stored: AppLanguage {
        AppLanguage(domain: defaults.persistentDomain(forName: suiteName))
    }

    func testAbsentDomainFollowsSystem() {
        XCTAssertEqual(AppLanguage(domain: nil), .system)
        XCTAssertEqual(AppLanguage(domain: [:]), .system)
    }

    func testRegionalVariantsMapToSupportedLanguage() {
        XCTAssertEqual(AppLanguage(domain: ["AppleLanguages": ["zh-Hans-CN"]]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage(domain: ["AppleLanguages": ["en-GB", "zh-Hans"]]), .english)
    }

    func testUnsupportedLanguageFollowsSystem() {
        XCTAssertEqual(AppLanguage(domain: ["AppleLanguages": ["fr"]]), .system)
    }

    func testStoreRoundTrips() {
        AppLanguage.simplifiedChinese.store(in: defaults)
        XCTAssertEqual(stored, .simplifiedChinese)
        AppLanguage.english.store(in: defaults)
        XCTAssertEqual(stored, .english)
    }

    func testStoringSystemRemovesKey() {
        AppLanguage.english.store(in: defaults)
        AppLanguage.system.store(in: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName)?["AppleLanguages"])
        XCTAssertEqual(stored, .system)
    }
}
