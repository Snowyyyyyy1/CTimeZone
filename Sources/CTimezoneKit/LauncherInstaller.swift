import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Installs the windowless Claude launcher that ships inside CTimeZone.app
/// into ~/Applications, where the Dock, Spotlight and Raycast can reach it.
///
/// The installed copy is named after the current Desktop zone
/// ("Claude · Amsterdam"). Renames move the existing bundle so a Dock item
/// pointing at it keeps working; refreshes replace it in place.
public struct LauncherInstaller: Sendable {
    /// Info.plist key recording which template build an installed copy came from.
    public static let digestKey = "CTZTemplateDigest"
    static let iconName = "LauncherIcon"

    public let templateURL: URL
    public let applicationsDirectory: URL

    public init(
        templateURL: URL,
        applicationsDirectory: URL = FileManager.default
            .homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    ) {
        self.templateURL = templateURL
        self.applicationsDirectory = applicationsDirectory
    }

    /// The template embedded in the running app, if this build has one.
    public static func embeddedTemplate(in bundle: Bundle = .main) -> URL? {
        let url = bundle.bundleURL.appendingPathComponent("Contents/Library/Helpers/ClaudeLauncher.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Naming

    public static func displayName(for mode: DesktopMode) -> String {
        switch mode {
        case .system: return "Claude \u{00B7} System Time"
        case .fixed(let zone): return "Claude \u{00B7} \(city(of: zone))"
        }
    }

    /// "America/New_York" -> "New York". Never contains a path separator.
    static func city(of zone: String) -> String {
        let last = zone.split(separator: "/").last.map(String.init) ?? zone
        return last.replacingOccurrences(of: "_", with: " ")
    }

    public func destination(for mode: DesktopMode) -> URL {
        applicationsDirectory.appendingPathComponent(Self.displayName(for: mode) + ".app")
    }

    // MARK: - Freshness

    /// True when `installed` exists, carries the expected name, and was built
    /// from the current template.
    public func isCurrent(_ installed: URL, for mode: DesktopMode) -> Bool {
        // Compare paths: appendingPathComponent adds a trailing slash once the
        // bundle exists on disk, which makes otherwise equal URLs unequal.
        guard installed.standardizedFileURL.path == destination(for: mode).standardizedFileURL.path,
              let info = NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist")),
              let recorded = info[Self.digestKey] as? String,
              let current = try? templateDigest()
        else { return false }
        return recorded == current
    }

    func templateDigest() throws -> String {
        let executable = templateURL.appendingPathComponent("Contents/MacOS/ClaudeLauncher")
        let digest = SHA256.hash(data: try Data(contentsOf: executable))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Install / remove

    /// Creates or updates the launcher for `mode`. `existing` is the copy
    /// installed earlier, if any; it is moved rather than recreated so Dock
    /// items follow it.
    @discardableResult
    public func install(mode: DesktopMode, existing: URL?, icon: NSImage?) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: applicationsDirectory, withIntermediateDirectories: true)

        // Stage on the same volume so the final swap is a rename.
        let staging = applicationsDirectory.appendingPathComponent(".ctz-launcher-\(UUID().uuidString).app")
        defer { try? fm.removeItem(at: staging) }
        try run("/usr/bin/ditto", [templateURL.path, staging.path])

        let infoURL = staging.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let hasIcon = try icon.map { try writeICNS($0, into: staging) } != nil
        let patched = Self.patchedInfo(
            info, name: Self.displayName(for: mode), digest: try templateDigest(), customIcon: hasIcon
        )
        try PropertyListSerialization.data(fromPropertyList: patched, format: .xml, options: 0)
            .write(to: infoURL)
        // Editing Info.plist invalidates the template's signature.
        try run("/usr/bin/codesign", ["--force", "--sign", "-", staging.path])

        let target = destination(for: mode)
        if let existing, existing.standardizedFileURL.path != target.standardizedFileURL.path,
           fm.fileExists(atPath: existing.path) {
            if fm.fileExists(atPath: target.path) { try fm.trashItem(at: target, resultingItemURL: nil) }
            try fm.moveItem(at: existing, to: target)
        }
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: staging)
        } else {
            try fm.moveItem(at: staging, to: target)
        }
        LSRegisterURL(target as CFURL, true)
        return target
    }

    /// Moves the launcher to the Trash so removal can be undone.
    public func remove(_ installed: URL) throws {
        try FileManager.default.trashItem(at: installed, resultingItemURL: nil)
    }

    static func patchedInfo(_ info: [String: Any], name: String, digest: String, customIcon: Bool) -> [String: Any] {
        var info = info
        info["CFBundleName"] = name
        info["CFBundleDisplayName"] = name
        info[digestKey] = digest
        if customIcon {
            // An asset-catalog icon name would win over the .icns file.
            info.removeValue(forKey: "CFBundleIconName")
            info["CFBundleIconFile"] = iconName
        }
        return info
    }

    // MARK: - Icon

    /// The user's own Claude icon with a small CTimeZone badge, rendered on
    /// this machine only. Nil when Claude is not installed.
    public static func badgedClaudeIcon(badge: NSImage) -> NSImage? {
        let claudePath = ClaudeDesktopController.appPath
        guard FileManager.default.fileExists(atPath: claudePath) else { return nil }
        let base = NSWorkspace.shared.icon(forFile: claudePath)
        let size = NSSize(width: 1024, height: 1024)
        return NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let side = rect.width * 0.42
            badge.draw(in: NSRect(x: rect.maxX - side - rect.width * 0.02, y: rect.width * 0.02,
                                  width: side, height: side))
            return true
        }
    }

    private func writeICNS(_ image: NSImage, into bundle: URL) throws {
        let url = bundle.appendingPathComponent("Contents/Resources/\(Self.iconName).icns")
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.icns.identifier as CFString, sizes.count, nil
        ) else { throw CocoaError(.fileWriteUnknown) }
        for side in sizes {
            var rect = CGRect(x: 0, y: 0, width: side, height: side)
            guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { continue }
            CGImageDestinationAddImage(destination, cg, nil)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "LauncherInstaller", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "\(tool) exited with \(process.terminationStatus)"])
        }
    }
}
