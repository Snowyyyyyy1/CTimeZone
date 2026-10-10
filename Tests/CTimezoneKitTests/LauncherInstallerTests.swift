@testable import CTimezoneKit
import XCTest

final class LauncherInstallerTests: XCTestCase {
    private var root: URL!
    private var template: URL!
    private var applications: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("launcher-\(UUID().uuidString)")
        template = root.appendingPathComponent("ClaudeLauncher.app")
        applications = root.appendingPathComponent("Applications")
        try makeTemplate(executable: "/usr/bin/true")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDisplayNameUsesCity() {
        XCTAssertEqual(LauncherInstaller.displayName(for: .fixed("Europe/Amsterdam")), "Claude \u{00B7} Amsterdam")
        XCTAssertEqual(LauncherInstaller.displayName(for: .fixed("America/New_York")), "Claude \u{00B7} New York")
        XCTAssertEqual(LauncherInstaller.displayName(for: .fixed("UTC")), "Claude \u{00B7} UTC")
        XCTAssertEqual(LauncherInstaller.displayName(for: .system), "Claude \u{00B7} System Time")
    }

    func testPatchedInfoPrefersCustomIcon() {
        let info: [String: Any] = ["CFBundleIconName": "AppIcon", "CFBundleIconFile": "AppIcon", "Keep": 1]
        let patched = LauncherInstaller.patchedInfo(info, name: "Claude \u{00B7} Tokyo", digest: "abc", customIcon: true)
        XCTAssertNil(patched["CFBundleIconName"])
        XCTAssertEqual(patched["CFBundleIconFile"] as? String, "LauncherIcon")
        XCTAssertEqual(patched["CFBundleDisplayName"] as? String, "Claude \u{00B7} Tokyo")
        XCTAssertEqual(patched[LauncherInstaller.digestKey] as? String, "abc")
        XCTAssertEqual(patched["Keep"] as? Int, 1)
    }

    func testInstallCreatesSignedCurrentCopy() throws {
        let installer = LauncherInstaller(templateURL: template, applicationsDirectory: applications)
        let url = try installer.install(mode: .fixed("Europe/Amsterdam"), existing: nil, icon: nil)

        XCTAssertEqual(url.lastPathComponent, "Claude \u{00B7} Amsterdam.app")
        XCTAssertTrue(installer.isCurrent(url, for: .fixed("Europe/Amsterdam")))
        XCTAssertFalse(installer.isCurrent(url, for: .fixed("Asia/Tokyo")))
        // A directory URL (trailing slash) for the same bundle must still match.
        XCTAssertTrue(installer.isCurrent(URL(fileURLWithPath: url.path, isDirectory: true), for: .fixed("Europe/Amsterdam")))
        XCTAssertEqual(try shell("/usr/bin/codesign", ["--verify", url.path]), 0)
        XCTAssertEqual(try stagingLeftovers(), [])
    }

    func testZoneChangeRenamesInPlace() throws {
        let installer = LauncherInstaller(templateURL: template, applicationsDirectory: applications)
        let first = try installer.install(mode: .fixed("Europe/Amsterdam"), existing: nil, icon: nil)
        let marker = first.appendingPathComponent("Contents/marker")
        try Data().write(to: marker)

        let second = try installer.install(mode: .fixed("Asia/Tokyo"), existing: first, icon: nil)

        XCTAssertEqual(second.lastPathComponent, "Claude \u{00B7} Tokyo.app")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(installer.isCurrent(second, for: .fixed("Asia/Tokyo")))
        // The moved bundle is replaced with fresh contents at the new name.
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.appendingPathComponent("Contents/marker").path))
    }

    func testTemplateChangeMakesCopyStale() throws {
        let installer = LauncherInstaller(templateURL: template, applicationsDirectory: applications)
        let url = try installer.install(mode: .system, existing: nil, icon: nil)
        XCTAssertTrue(installer.isCurrent(url, for: .system))

        try FileManager.default.removeItem(at: template)
        try makeTemplate(executable: "/usr/bin/false")
        XCTAssertFalse(installer.isCurrent(url, for: .system))
    }

    // MARK: - Helpers

    private func makeTemplate(executable: String) throws {
        let macOS = template.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: executable, toPath: macOS.appendingPathComponent("ClaudeLauncher").path)
        let info: [String: Any] = [
            "CFBundleExecutable": "ClaudeLauncher",
            "CFBundleIdentifier": "test.launcher",
            "CFBundlePackageType": "APPL",
            "CFBundleIconName": "AppIcon"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: template.appendingPathComponent("Contents/Info.plist"))
    }

    private func stagingLeftovers() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: applications.path).filter { $0.hasPrefix(".ctz-launcher-") }
    }

    @discardableResult
    private func shell(_ tool: String, _ args: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
