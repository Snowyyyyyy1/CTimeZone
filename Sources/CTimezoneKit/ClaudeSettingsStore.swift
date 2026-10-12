import Foundation

/// Reads and writes `env.TZ` in `~/.claude/settings.json` while preserving
/// every unrelated value. Besides `env.TZ`, it only touches the entries the
/// time zone shield owns (see `shieldReadPaths` and `ShieldAdditions`); all
/// other keys are retained.
public struct ClaudeSettingsStore {
    public enum StoreError: Error, Equatable {
        /// The file exists but is not a JSON object at the root.
        case malformedRoot
        /// `env` exists but is not a JSON object.
        case malformedEnv
        /// A time zone identifier failed validation.
        case invalidTimeZone(String)
        /// `sandbox`, `sandbox.filesystem`, `sandbox.network`, `denyRead` or
        /// `allowWrite` has an unexpected type.
        case malformedSandbox
        /// `permissions`, `permissions.allow` or `permissions.deny` has an unexpected type.
        case malformedPermissions
    }

    /// Files that reveal the Mac's own time zone. `/etc/localtime` names the
    /// zone through its link target; the global preferences hold the selected city.
    public static let shieldReadPaths = [
        "/etc/localtime",
        "/private/etc/localtime",
        "/Library/Preferences/.GlobalPreferences.plist",
    ]

    /// Read deny rules for Claude's own file tools, which run outside the
    /// sandbox. Permission rules mark absolute paths with a leading `//`.
    public static var shieldReadRules: [String] {
        shieldReadPaths.map { "Read(/\($0))" }
    }

    /// Allow rule whose domain the sandbox also pre-allows. `sandbox.network.allowedDomains`
    /// rejects a bare `*`, but a `WebFetch(domain:*)` allow rule matches every host.
    public static let allowAllDomainsRule = "WebFetch(domain:*)"

    /// `sandbox.filesystem.allowWrite` entry that lets sandboxed commands
    /// write anywhere outside Claude Code's protected paths.
    public static let allowWriteEverywhere = "/"

    /// `sandbox.network` switches that lift the sandbox's socket limits.
    /// `allowAppleEvents` and `allowMachLookup` stay off: both let a command
    /// reach code outside the sandbox, which could read the time zone.
    public static let openNetworkKeys = ["allowLocalBinding", "allowAllUnixSockets"]

    /// What turning the shield on added besides its read denials, so turning
    /// it off removes only those.
    public struct ShieldAdditions: Equatable {
        /// `sandbox.enabled` was not true before.
        public var enabledSandbox = false
        /// `allowWriteEverywhere` and `openNetworkKeys` were added.
        public var openedSandbox = false
        /// `allowAllDomainsRule` was added to `permissions.allow`.
        public var allowedAllDomains = false

        public init(enabledSandbox: Bool = false, openedSandbox: Bool = false, allowedAllDomains: Bool = false) {
            self.enabledSandbox = enabledSandbox
            self.openedSandbox = openedSandbox
            self.allowedAllDomains = allowedAllDomains
        }
    }

    public let settingsURL: URL
    private let fileManager: FileManager

    public init(
        settingsURL: URL = ClaudeSettingsStore.defaultSettingsURL,
        fileManager: FileManager = .default
    ) {
        self.settingsURL = settingsURL
        self.fileManager = fileManager
    }

    public static var defaultSettingsURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// Current `env.TZ`, or `nil` when the file/env/key is absent.
    /// Throws when the file is present but malformed, so callers never
    /// overwrite a structure they failed to understand.
    public func currentTimeZone() throws -> String? {
        try Self.dictionary(readRoot()["env"], or: .malformedEnv)["TZ"] as? String
    }

    /// Sets `env.TZ` to `identifier`, creating the file and/or `env` object when
    /// absent. Writes atomically after backing up any existing file.
    @discardableResult
    public func setTimeZone(_ identifier: String) throws -> URL? {
        guard Timezones.isValid(identifier) else {
            throw StoreError.invalidTimeZone(identifier)
        }
        return try mutateEnv { env in env["TZ"] = identifier }
    }

    /// Removes only `env.TZ`, preserving sibling keys in `env` and the rest of
    /// the document. No-op (no write) when the key is already absent.
    @discardableResult
    public func removeTimeZone() throws -> URL? {
        try mutateEnv { env in env.removeValue(forKey: "TZ") }
    }

    // MARK: - Time zone shield

    /// True when the sandbox is on and every shield entry is present, so
    /// Claude Code's commands and file tools cannot read the Mac's time zone.
    public func isTimeZoneShieldOn() throws -> Bool {
        let parts = try ShieldParts(try readRoot())
        return parts.sandbox["enabled"] as? Bool == true
            && Set(Self.shieldReadPaths).isSubset(of: parts.denyRead)
            && Set(Self.shieldReadRules).isSubset(of: parts.deny)
    }

    /// Turns the sandbox on and adds the shield's read denials to
    /// `sandbox.filesystem.denyRead` and `permissions.deny`.
    /// When the sandbox was off and holds no settings of the user's own, it
    /// also opens writes, sockets and every domain, so the shield blocks
    /// little beyond the time zone reads. The caller keeps `added` to undo
    /// exactly these.
    public func enableTimeZoneShield() throws -> (backup: URL?, added: ShieldAdditions) {
        var added = ShieldAdditions()
        let backup = try mutateRoot { root in
            var parts = try ShieldParts(root)
            added.enabledSandbox = parts.sandbox["enabled"] as? Bool != true
            if added.enabledSandbox && parts.sandbox.keys.allSatisfy({ $0 == "enabled" }) {
                parts.allowWrite = [Self.allowWriteEverywhere]
                for key in Self.openNetworkKeys { parts.network[key] = true }
                added.openedSandbox = true
                if !parts.allow.contains(Self.allowAllDomainsRule) {
                    parts.allow.append(Self.allowAllDomainsRule)
                    added.allowedAllDomains = true
                }
            }
            parts.sandbox["enabled"] = true
            parts.denyRead += Self.shieldReadPaths.filter { !parts.denyRead.contains($0) }
            parts.deny += Self.shieldReadRules.filter { !parts.deny.contains($0) }
            parts.write(into: &root)
        }
        return (backup, added)
    }

    /// Removes the shield's read denials and whatever `added` records,
    /// dropping containers they leave empty.
    @discardableResult
    public func disableTimeZoneShield(undoing added: ShieldAdditions) throws -> URL? {
        try mutateRoot { root in
            var parts = try ShieldParts(root)
            parts.denyRead.removeAll { Self.shieldReadPaths.contains($0) }
            parts.deny.removeAll { Self.shieldReadRules.contains($0) }
            if added.enabledSandbox { parts.sandbox.removeValue(forKey: "enabled") }
            if added.openedSandbox {
                for key in Self.openNetworkKeys { parts.network.removeValue(forKey: key) }
                parts.allowWrite.removeAll { $0 == Self.allowWriteEverywhere }
            }
            if added.allowedAllDomains { parts.allow.removeAll { $0 == Self.allowAllDomainsRule } }
            parts.write(into: &root)
        }
    }

    /// The containers the shield edits, read once and written back together.
    /// Writing drops any container left empty.
    private struct ShieldParts {
        var sandbox: [String: Any]
        var filesystem: [String: Any]
        var network: [String: Any]
        var permissions: [String: Any]
        var denyRead: [String]
        var allowWrite: [String]
        var allow: [String]
        var deny: [String]

        init(_ root: [String: Any]) throws {
            sandbox = try ClaudeSettingsStore.dictionary(root["sandbox"], or: .malformedSandbox)
            filesystem = try ClaudeSettingsStore.dictionary(sandbox["filesystem"], or: .malformedSandbox)
            network = try ClaudeSettingsStore.dictionary(sandbox["network"], or: .malformedSandbox)
            permissions = try ClaudeSettingsStore.dictionary(root["permissions"], or: .malformedPermissions)
            denyRead = try ClaudeSettingsStore.strings(filesystem["denyRead"], or: .malformedSandbox)
            allowWrite = try ClaudeSettingsStore.strings(filesystem["allowWrite"], or: .malformedSandbox)
            allow = try ClaudeSettingsStore.strings(permissions["allow"], or: .malformedPermissions)
            deny = try ClaudeSettingsStore.strings(permissions["deny"], or: .malformedPermissions)
        }

        func write(into root: inout [String: Any]) {
            var filesystem = filesystem, sandbox = sandbox, permissions = permissions
            filesystem["denyRead"] = denyRead.isEmpty ? nil : denyRead
            filesystem["allowWrite"] = allowWrite.isEmpty ? nil : allowWrite
            sandbox["filesystem"] = filesystem.isEmpty ? nil : filesystem
            sandbox["network"] = network.isEmpty ? nil : network
            permissions["allow"] = allow.isEmpty ? nil : allow
            permissions["deny"] = deny.isEmpty ? nil : deny
            root["sandbox"] = sandbox.isEmpty ? nil : sandbox
            root["permissions"] = permissions.isEmpty ? nil : permissions
        }
    }

    // MARK: - Internals

    private func readRoot() throws -> [String: Any] {
        guard fileManager.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return [:] }
        let parsed = try JSONSerialization.jsonObject(with: data)
        guard let dict = parsed as? [String: Any] else { throw StoreError.malformedRoot }
        return dict
    }

    /// An absent value reads as empty; any other non-object type throws.
    private static func dictionary(_ value: Any?, or error: StoreError) throws -> [String: Any] {
        guard let value else { return [:] }
        guard let dict = value as? [String: Any] else { throw error }
        return dict
    }

    private static func strings(_ value: Any?, or error: StoreError) throws -> [String] {
        guard let value else { return [] }
        guard let array = value as? [String] else { throw error }
        return array
    }

    private func mutateEnv(_ body: (inout [String: Any]) -> Void) throws -> URL? {
        try mutateRoot { root in
            var env = try Self.dictionary(root["env"], or: .malformedEnv)
            let before = env
            body(&env)
            // Leave the root untouched when env is unchanged, so removing TZ
            // from a file without one never adds an empty `env` object.
            if before as NSDictionary != env as NSDictionary {
                root["env"] = env
            }
        }
    }

    private func mutateRoot(_ body: (inout [String: Any]) throws -> Void) throws -> URL? {
        let fileExists = fileManager.fileExists(atPath: settingsURL.path)
        var root = try readRoot()

        let before = root
        try body(&root)
        // No-op when nothing changed. This must not depend on `fileExists`:
        // a no-op on a missing/empty file must not create the file.
        if before as NSDictionary == root as NSDictionary {
            return nil
        }

        let output = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )

        let backupURL = fileExists ? try backupExistingFile() : nil
        try writeAtomically(output)
        return backupURL
    }

    /// Copies the existing settings file to a timestamped sibling with `0600`.
    private func backupExistingFile() throws -> URL {
        let stamp = Self.timestampFormatter.string(from: Date())
        let backupURL = settingsURL
            .deletingLastPathComponent()
            .appendingPathComponent("settings.json.\(stamp).bak")
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: settingsURL, to: backupURL)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        return backupURL
    }

    /// Writes via a temp file + `replaceItemAt` to keep the update atomic.
    /// The existing file's POSIX mode is preserved; new files default to `0600`.
    private func writeAtomically(_ data: Data) throws {
        let directory = settingsURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let existingMode = try? fileManager
            .attributesOfItem(atPath: settingsURL.path)[.posixPermissions] as? NSNumber
        let targetMode: Int = existingMode?.intValue ?? 0o600

        let tempURL = directory.appendingPathComponent(".settings.json.\(UUID().uuidString).tmp")
        try data.write(to: tempURL, options: [.atomic])
        try? fileManager.setAttributes([.posixPermissions: targetMode], ofItemAtPath: tempURL.path)

        if fileManager.fileExists(atPath: settingsURL.path) {
            _ = try fileManager.replaceItemAt(settingsURL, withItemAt: tempURL)
        } else {
            try fileManager.moveItem(at: tempURL, to: settingsURL)
        }
        try? fileManager.setAttributes([.posixPermissions: targetMode], ofItemAtPath: settingsURL.path)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
