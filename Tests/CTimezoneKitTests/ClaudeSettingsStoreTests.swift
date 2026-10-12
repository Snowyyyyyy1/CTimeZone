@testable import CTimezoneKit
import XCTest

final class ClaudeSettingsStoreTests: XCTestCase {
    private var directory: URL!
    private var settingsURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ctz-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settingsURL = directory.appendingPathComponent("settings.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store() -> ClaudeSettingsStore {
        ClaudeSettingsStore(settingsURL: settingsURL)
    }

    private func write(_ json: String) throws {
        try Data(json.utf8).write(to: settingsURL)
    }

    private func readRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: settingsURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Reading

    func testCurrentTimeZoneNilWhenFileAbsent() throws {
        XCTAssertNil(try store().currentTimeZone())
    }

    func testCurrentTimeZoneNilWhenEnvAbsent() throws {
        try write(#"{"model":"opus"}"#)
        XCTAssertNil(try store().currentTimeZone())
    }

    func testCurrentTimeZoneReadsValue() throws {
        try write(#"{"env":{"TZ":"Europe/Amsterdam"}}"#)
        XCTAssertEqual(try store().currentTimeZone(), "Europe/Amsterdam")
    }

    func testMalformedRootThrows() throws {
        try write("[1,2,3]")
        XCTAssertThrowsError(try store().currentTimeZone()) {
            XCTAssertEqual($0 as? ClaudeSettingsStore.StoreError, .malformedRoot)
        }
    }

    func testMalformedEnvThrows() throws {
        try write(#"{"env":"nope"}"#)
        XCTAssertThrowsError(try store().currentTimeZone()) {
            XCTAssertEqual($0 as? ClaudeSettingsStore.StoreError, .malformedEnv)
        }
    }

    func testInvalidTimeZoneRejected() throws {
        XCTAssertThrowsError(try store().setTimeZone("Not/AZone")) {
            XCTAssertEqual($0 as? ClaudeSettingsStore.StoreError, .invalidTimeZone("Not/AZone"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    // MARK: - Writing

    func testSetCreatesFileAndEnvWhenAbsent() throws {
        XCTAssertNil(try store().setTimeZone("Europe/Amsterdam"))
        let root = try readRoot()
        XCTAssertEqual((root["env"] as? [String: Any])?["TZ"] as? String, "Europe/Amsterdam")
    }

    func testSetPreservesUnrelatedValues() throws {
        try write(#"{"model":"opus","env":{"OTHER":"keep","TZ":"Asia/Shanghai"},"nested":{"a":[1,2]}}"#)
        _ = try store().setTimeZone("Europe/Amsterdam")
        let root = try readRoot()
        XCTAssertEqual(root["model"] as? String, "opus")
        XCTAssertEqual((root["nested"] as? [String: Any])?["a"] as? [Int], [1, 2])
        let env = try XCTUnwrap(root["env"] as? [String: Any])
        XCTAssertEqual(env["OTHER"] as? String, "keep")
        XCTAssertEqual(env["TZ"] as? String, "Europe/Amsterdam")
    }

    func testSetMalformedRootDoesNotOverwrite() throws {
        try write(#"[1,2,3]"#)
        XCTAssertThrowsError(try store().setTimeZone("Europe/Amsterdam")) {
            XCTAssertEqual($0 as? ClaudeSettingsStore.StoreError, .malformedRoot)
        }
        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), "[1,2,3]")
    }

    func testSetMalformedEnvDoesNotOverwrite() throws {
        try write(#"{"env":42}"#)
        XCTAssertThrowsError(try store().setTimeZone("Europe/Amsterdam")) {
            XCTAssertEqual($0 as? ClaudeSettingsStore.StoreError, .malformedEnv)
        }
        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), #"{"env":42}"#)
    }

    func testSetCreatesTimestampedBackup() throws {
        try write(#"{"env":{"TZ":"Asia/Shanghai"}}"#)
        let backup = try store().setTimeZone("Europe/Amsterdam")
        let backupURL = try XCTUnwrap(backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertEqual(try String(contentsOf: backupURL, encoding: .utf8), #"{"env":{"TZ":"Asia/Shanghai"}}"#)
    }

    func testSetIsNoOpWhenUnchanged() throws {
        try write(#"{"env":{"TZ":"Europe/Amsterdam"}}"#)
        XCTAssertNil(try store().setTimeZone("Europe/Amsterdam"))
    }

    // MARK: - Reset

    func testRemoveTimeZonePreservesEnvSiblingsAndRoot() throws {
        try write(#"{"model":"opus","env":{"OTHER":"keep","TZ":"Europe/Amsterdam"}}"#)
        _ = try store().removeTimeZone()
        let root = try readRoot()
        XCTAssertEqual(root["model"] as? String, "opus")
        let env = try XCTUnwrap(root["env"] as? [String: Any])
        XCTAssertNil(env["TZ"])
        XCTAssertEqual(env["OTHER"] as? String, "keep")
    }

    func testRemoveTimeZoneNoOpWhenAbsent() throws {
        try write(#"{"env":{"OTHER":"keep"}}"#)
        XCTAssertNil(try store().removeTimeZone())
    }

    func testRemoveTimeZoneOnMissingFileDoesNotCreateFileOrBackup() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
        XCTAssertNil(try store().removeTimeZone())
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.contains(".bak") }
        XCTAssertTrue(backups.isEmpty)
    }

    func testRemoveTimeZoneCreatesBackupWhenFileExists() throws {
        try write(#"{"env":{"TZ":"Europe/Amsterdam"}}"#)
        let backup = try store().removeTimeZone()
        XCTAssertNotNil(backup)
        let env = try XCTUnwrap(try readRoot()["env"] as? [String: Any])
        XCTAssertNil(env["TZ"])
    }

    // MARK: - Permissions

    private func mode(of url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attrs[.posixPermissions] as? NSNumber).intValue
    }

    func testSetPreservesExistingFileMode0644() throws {
        try write(#"{"env":{"TZ":"Asia/Shanghai"}}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: settingsURL.path)
        _ = try store().setTimeZone("Europe/Amsterdam")
        XCTAssertEqual(try mode(of: settingsURL), 0o644)
    }

    func testSetPreservesExistingFileMode0640() throws {
        try write(#"{"env":{"TZ":"Asia/Shanghai"}}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: settingsURL.path)
        _ = try store().setTimeZone("Europe/Amsterdam")
        XCTAssertEqual(try mode(of: settingsURL), 0o640)
    }

    func testNewFileDefaultsTo0600() throws {
        XCTAssertNil(try store().setTimeZone("Europe/Amsterdam"))
        XCTAssertEqual(try mode(of: settingsURL), 0o600)
    }

    func testBackupIs0600() throws {
        try write(#"{"env":{"TZ":"Asia/Shanghai"}}"#)
        let backup = try XCTUnwrap(try store().setTimeZone("Europe/Amsterdam"))
        XCTAssertEqual(try mode(of: backup), 0o600)
    }

    // MARK: - Time zone shield

    private let paths = ClaudeSettingsStore.shieldReadPaths
    private let rules = ClaudeSettingsStore.shieldReadRules

    func testShieldRulesUseAbsolutePathPrefix() {
        XCTAssertEqual(rules.first, "Read(//etc/localtime)")
    }

    func testShieldOffWhenFileAbsent() throws {
        XCTAssertFalse(try store().isTimeZoneShieldOn())
    }

    func testEnableShieldOnMissingFile() throws {
        let result = try store().enableTimeZoneShield()
        XCTAssertNil(result.backup)
        XCTAssertEqual(result.added, .init(enabledSandbox: true, openedSandbox: true, allowedAllDomains: true))
        XCTAssertTrue(try store().isTimeZoneShieldOn())
        let root = try readRoot()
        let sandbox = try XCTUnwrap(root["sandbox"] as? [String: Any])
        let filesystem = try XCTUnwrap(sandbox["filesystem"] as? [String: Any])
        XCTAssertEqual(filesystem["denyRead"] as? [String], paths)
        XCTAssertEqual(filesystem["allowWrite"] as? [String], ["/"])
        XCTAssertEqual(sandbox["network"] as? NSDictionary, ["allowLocalBinding": true, "allowAllUnixSockets": true] as NSDictionary)
        let permissions = try XCTUnwrap(root["permissions"] as? [String: Any])
        XCTAssertEqual(permissions["allow"] as? [String], [ClaudeSettingsStore.allowAllDomainsRule])
        XCTAssertEqual(permissions["deny"] as? [String], rules)
    }

    func testEnableShieldKeepsUserSandboxSettings() throws {
        try write(#"{"sandbox":{"enabled":false,"network":{"allowedDomains":["github.com"]}}}"#)
        let result = try store().enableTimeZoneShield()
        XCTAssertEqual(result.added, .init(enabledSandbox: true))
        let root = try readRoot()
        let sandbox = try XCTUnwrap(root["sandbox"] as? [String: Any])
        XCTAssertEqual(sandbox["network"] as? NSDictionary, ["allowedDomains": ["github.com"]] as NSDictionary)
        XCTAssertNil((sandbox["filesystem"] as? [String: Any])?["allowWrite"])
        XCTAssertNil((root["permissions"] as? [String: Any])?["allow"])
    }

    func testEnableShieldOpensSandboxWhenOnlyDisabled() throws {
        try write(#"{"sandbox":{"enabled":false}}"#)
        let result = try store().enableTimeZoneShield()
        XCTAssertEqual(result.added, .init(enabledSandbox: true, openedSandbox: true, allowedAllDomains: true))
        try store().disableTimeZoneShield(undoing: result.added)
        // `enabled: false` is the default, so restoring drops the key.
        XCTAssertEqual(try readRoot() as NSDictionary, [:] as NSDictionary)
    }

    func testDisableShieldKeepsAllowWriteEntriesAddedLater() throws {
        let result = try store().enableTimeZoneShield()
        var root = try readRoot()
        var sandbox = try XCTUnwrap(root["sandbox"] as? [String: Any])
        var filesystem = try XCTUnwrap(sandbox["filesystem"] as? [String: Any])
        filesystem["allowWrite"] = ["/", "~/.kube"]
        sandbox["filesystem"] = filesystem
        root["sandbox"] = sandbox
        try JSONSerialization.data(withJSONObject: root).write(to: settingsURL)
        try store().disableTimeZoneShield(undoing: result.added)
        XCTAssertEqual(try readRoot() as NSDictionary, ["sandbox": ["filesystem": ["allowWrite": ["~/.kube"]]]] as NSDictionary)
    }

    func testEnableShieldDoesNotDuplicateAllowAllRule() throws {
        try write(#"{"permissions":{"allow":["WebFetch(domain:*)"]}}"#)
        let result = try store().enableTimeZoneShield()
        XCTAssertEqual(result.added, .init(enabledSandbox: true, openedSandbox: true))
        try store().disableTimeZoneShield(undoing: result.added)
        XCTAssertEqual(try readRoot() as NSDictionary, ["permissions": ["allow": ["WebFetch(domain:*)"]]] as NSDictionary)
    }

    func testEnableShieldMergesWithUserEntries() throws {
        try write(#"""
        {"env":{"TZ":"Asia/Tokyo"},"sandbox":{"enabled":true,"excludedCommands":["gh *"],
         "filesystem":{"denyRead":["~/.ssh","/etc/localtime"]}},
         "permissions":{"allow":["Bash(ls)"],"deny":["Read(./.env)"]}}
        """#)
        let result = try store().enableTimeZoneShield()
        XCTAssertNotNil(result.backup)
        XCTAssertEqual(result.added, .init())
        let root = try readRoot()
        XCTAssertEqual((root["env"] as? [String: Any])?["TZ"] as? String, "Asia/Tokyo")
        let sandbox = try XCTUnwrap(root["sandbox"] as? [String: Any])
        XCTAssertEqual(sandbox["excludedCommands"] as? [String], ["gh *"])
        XCTAssertEqual(
            (sandbox["filesystem"] as? [String: Any])?["denyRead"] as? [String],
            ["~/.ssh", "/etc/localtime", "/private/etc/localtime", "/Library/Preferences/.GlobalPreferences.plist"]
        )
        let permissions = try XCTUnwrap(root["permissions"] as? [String: Any])
        XCTAssertEqual(permissions["allow"] as? [String], ["Bash(ls)"])
        XCTAssertEqual(permissions["deny"] as? [String], ["Read(./.env)"] + rules)
    }

    func testEnableShieldIsNoOpWhenAlreadyOn() throws {
        _ = try store().enableTimeZoneShield()
        let again = try store().enableTimeZoneShield()
        XCTAssertNil(again.backup)
        XCTAssertEqual(again.added, .init())
    }

    func testShieldOffWhenSandboxDisabled() throws {
        _ = try store().enableTimeZoneShield()
        var root = try readRoot()
        var sandbox = try XCTUnwrap(root["sandbox"] as? [String: Any])
        sandbox["enabled"] = false
        root["sandbox"] = sandbox
        try JSONSerialization.data(withJSONObject: root).write(to: settingsURL)
        XCTAssertFalse(try store().isTimeZoneShieldOn())
    }

    func testDisableShieldRestoresOriginalDocument() throws {
        try write(#"{"env":{"TZ":"Asia/Tokyo"}}"#)
        let result = try store().enableTimeZoneShield()
        try store().disableTimeZoneShield(undoing: result.added)
        XCTAssertEqual(try readRoot() as NSDictionary, ["env": ["TZ": "Asia/Tokyo"]] as NSDictionary)
    }

    func testDisableShieldKeepsUserSandboxAndEntries() throws {
        try write(#"""
        {"sandbox":{"enabled":true,"filesystem":{"denyRead":["~/.ssh"]}},"permissions":{"deny":["Read(./.env)"]}}
        """#)
        let result = try store().enableTimeZoneShield()
        try store().disableTimeZoneShield(undoing: result.added)
        let root = try readRoot()
        let sandbox = try XCTUnwrap(root["sandbox"] as? [String: Any])
        XCTAssertEqual(sandbox["enabled"] as? Bool, true)
        XCTAssertEqual((sandbox["filesystem"] as? [String: Any])?["denyRead"] as? [String], ["~/.ssh"])
        XCTAssertEqual((root["permissions"] as? [String: Any])?["deny"] as? [String], ["Read(./.env)"])
    }

    func testDisableShieldOnMissingFileDoesNotCreateFile() throws {
        XCTAssertNil(try store().disableTimeZoneShield(undoing: .init(enabledSandbox: true, openedSandbox: true, allowedAllDomains: true)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    func testEnableShieldMalformedSandboxDoesNotOverwrite() throws {
        try write(#"{"sandbox":{"filesystem":{"denyRead":"~/.ssh"}}}"#)
        XCTAssertThrowsError(try store().enableTimeZoneShield()) {
            XCTAssertEqual($0 as? ClaudeSettingsStore.StoreError, .malformedSandbox)
        }
        XCTAssertEqual(
            try String(contentsOf: settingsURL, encoding: .utf8),
            #"{"sandbox":{"filesystem":{"denyRead":"~/.ssh"}}}"#
        )
    }

    func testEnableShieldMalformedPermissionsThrows() throws {
        try write(#"{"permissions":{"deny":[1]}}"#)
        XCTAssertThrowsError(try store().enableTimeZoneShield()) {
            XCTAssertEqual($0 as? ClaudeSettingsStore.StoreError, .malformedPermissions)
        }
    }
}
