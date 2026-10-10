import Foundation

/// Reads and writes `env.TZ` in `~/.claude/settings.json` while preserving
/// every unrelated value. Only the `TZ` key inside the top-level `env` object
/// is ever touched; all other keys (and the rest of the file) are retained.
public struct ClaudeSettingsStore {
    public enum StoreError: Error, Equatable {
        /// The file exists but is not a JSON object at the root.
        case malformedRoot
        /// `env` exists but is not a JSON object.
        case malformedEnv
        /// A time zone identifier failed validation.
        case invalidTimeZone(String)
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
        guard fileManager.fileExists(atPath: settingsURL.path) else { return nil }
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty else { return nil }
        let root = try JSONSerialization.jsonObject(with: data)
        guard let dict = root as? [String: Any] else { throw StoreError.malformedRoot }
        guard let envAny = dict["env"] else { return nil }
        guard let env = envAny as? [String: Any] else { throw StoreError.malformedEnv }
        return env["TZ"] as? String
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

    // MARK: - Internals

    private func mutateEnv(_ body: (inout [String: Any]) -> Void) throws -> URL? {
        var root: [String: Any] = [:]
        let fileExists = fileManager.fileExists(atPath: settingsURL.path)

        if fileExists {
            let data = try Data(contentsOf: settingsURL)
            if !data.isEmpty {
                let parsed = try JSONSerialization.jsonObject(with: data)
                guard let dict = parsed as? [String: Any] else { throw StoreError.malformedRoot }
                root = dict
            }
        }

        var env: [String: Any] = [:]
        if let envAny = root["env"] {
            guard let existing = envAny as? [String: Any] else { throw StoreError.malformedEnv }
            env = existing
        }

        let before = env
        body(&env)
        // No-op when the env mapping is unchanged. This must not depend on
        // `fileExists`: removing TZ from a missing/empty file changes nothing
        // and must not create the file or an empty `env` object.
        if before as NSDictionary == env as NSDictionary {
            return nil
        }

        root["env"] = env
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
