@testable import CTimezoneKit
import XCTest

final class SystemTimeZoneResolverTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctz-tz-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Creates a fake `/etc/localtime`-style symlink pointing at a zoneinfo path.
    private func makeLink(to zoneinfoPath: String) throws -> String {
        let link = directory.appendingPathComponent("localtime")
        try? FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: zoneinfoPath)
        return link.path
    }

    func testResolvesSimpleZone() throws {
        let link = try makeLink(to: "/var/db/timezone/zoneinfo/Asia/Shanghai")
        XCTAssertEqual(
            SystemTimeZoneResolver.zoneinfoIdentifier(fromLinkAtPath: link),
            "Asia/Shanghai"
        )
    }

    func testResolvesNestedZone() throws {
        let link = try makeLink(to: "/var/db/timezone/zoneinfo/America/Argentina/Buenos_Aires")
        XCTAssertEqual(
            SystemTimeZoneResolver.zoneinfoIdentifier(fromLinkAtPath: link),
            "America/Argentina/Buenos_Aires"
        )
    }

    func testNonZoneinfoTargetReturnsNil() throws {
        let link = try makeLink(to: "/usr/share/whatever/Asia/Tokyo")
        XCTAssertNil(SystemTimeZoneResolver.zoneinfoIdentifier(fromLinkAtPath: link))
    }

    func testMissingLinkReturnsNil() {
        XCTAssertNil(SystemTimeZoneResolver.zoneinfoIdentifier(fromLinkAtPath: "/no/such/link"))
    }

    func testSystemLinkTakesPrecedenceOverInheritedProcessTZ() throws {
        // The link says Shanghai; the process (here) reports Amsterdam. The link wins.
        let link = try makeLink(to: "/var/db/timezone/zoneinfo/Asia/Shanghai")
        let info = SystemTimeZoneResolver.resolve(
            linkPath: link,
            processIdentifier: "Europe/Amsterdam"
        )
        XCTAssertEqual(info.identifier, "Asia/Shanghai")
        XCTAssertEqual(info.source, .systemLink)
        XCTAssertTrue(info.isAuthoritative)
    }

    func testFallsBackToProcessTZWhenLinkUnresolvable() {
        let info = SystemTimeZoneResolver.resolve(
            linkPath: "/no/such/link",
            processIdentifier: "Europe/Amsterdam"
        )
        XCTAssertEqual(info.identifier, "Europe/Amsterdam")
        XCTAssertEqual(info.source, .processFallback)
        XCTAssertFalse(info.isAuthoritative)
    }

    func testUnknownWhenNothingResolvable() {
        let info = SystemTimeZoneResolver.resolve(
            linkPath: "/no/such/link",
            processIdentifier: "Not/AZone"
        )
        XCTAssertNil(info.identifier)
        XCTAssertEqual(info.source, .unknown)
    }
}
