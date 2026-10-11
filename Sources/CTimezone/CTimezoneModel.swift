import AppKit
import CTimezoneKit
import Foundation
import Observation

@MainActor
@Observable
final class CTimezoneModel {
    struct Banner: Equatable {
        enum Kind { case info, error }
        let kind: Kind
        let text: String
    }

    // Selection for the shared Claude Code / URL Handler config.
    var selectedTimeZone: String?
    var searchText = ""
    var isBusy = false
    var banner: Banner?

    private(set) var cliConfiguredTZ: String?
    /// Whether Claude Code's sandbox blocks reading the Mac's time zone.
    private(set) var shieldIsOn = false
    private(set) var systemZone: SystemTimeZoneInfo
    private(set) var desktopMode: DesktopMode
    private(set) var desktopStatus: ClaudeDesktopController.Status
    /// Installed Dock launcher, if the user added one.
    private(set) var launcherURL: URL?

    let catalog: [String]
    /// City names in the interface language; the language only changes on relaunch.
    let cityNames: [String: String]
    let locations: [String: GeoPoint]

    private let store: ClaudeSettingsStore
    private let desktop: ClaudeDesktopController
    private let defaults: UserDefaults
    private let launcher = LauncherInstaller.embeddedTemplate().map { LauncherInstaller(templateURL: $0) }
    private static let launcherPathKey = "launcherPath"
    /// Set when turning the shield on also turned the sandbox on, so turning
    /// it off restores the user's sandbox choice.
    private static let shieldEnabledSandboxKey = "shieldEnabledSandbox"

    init(
        store: ClaudeSettingsStore = ClaudeSettingsStore(),
        desktop: ClaudeDesktopController = ClaudeDesktopController(),
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.desktop = desktop
        self.defaults = defaults
        self.catalog = Timezones.catalog()
        self.cityNames = Timezones.cityNames(
            for: catalog,
            locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        )
        self.locations = ZoneLocations.load()
        self.systemZone = SystemTimeZoneResolver.resolve()

        let configured = try? store.currentTimeZone()
        self.cliConfiguredTZ = configured ?? nil
        self.selectedTimeZone = configured ?? nil
        self.shieldIsOn = (try? store.isTimeZoneShieldOn()) ?? false
        self.desktopMode = DesktopModePreference.load(defaults, configuredTZ: configured ?? nil)
        self.desktopStatus = desktop.status()
        self.launcherURL = defaults.string(forKey: Self.launcherPathKey)
            .map { URL(fileURLWithPath: $0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        Task { await syncLauncher() }
    }

    var filteredCatalog: [String] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return catalog }
        // Match "new york" against "America/New_York".
        let normalized = query.replacingOccurrences(of: " ", with: "_")
        return catalog.filter {
            $0.localizedCaseInsensitiveContains(normalized)
                || cityNames[$0]?.localizedCaseInsensitiveContains(query) == true
        }
    }

    /// Zone shown on the Claude clock: the pending selection, else the Desktop target.
    var previewIdentifier: String? {
        selectedTimeZone ?? desktopTargetIdentifier
    }

    /// True when applying the selection would change settings.json or the Desktop target.
    var hasUnappliedSelection: Bool {
        guard let selected = selectedTimeZone else { return false }
        return selected != cliConfiguredTZ || desktopMode != .fixed(selected)
    }

    /// Whether the running Desktop instance already uses the Desktop target.
    var desktopIsInSync: Bool {
        guard case .value(let tz) = desktopStatus.observedTZ else { return false }
        return tz == desktopTargetIdentifier
    }

    /// Effective zone used for the Desktop launch environment.
    var desktopTargetIdentifier: String? {
        switch desktopMode {
        case .fixed(let tz): return tz
        case .system: return systemZone.identifier
        }
    }

    var desktopModeLabel: String {
        switch desktopMode {
        case .system: return String(localized: "System (\(systemZone.identifier ?? String(localized: "unknown")))")
        case .fixed(let tz): return tz
        }
    }

    func refresh() {
        systemZone = SystemTimeZoneResolver.resolve()
        // Keep the last known value only when the file is unreadable; an absent
        // key must clear it so external removals show up.
        do { cliConfiguredTZ = try store.currentTimeZone() } catch {}
        do { shieldIsOn = try store.isTimeZoneShieldOn() } catch {}
        desktopStatus = desktop.status()
    }

    /// Writes `env.TZ` in settings.json and records the Desktop target.
    /// Does not touch the running Desktop process.
    func apply() async {
        guard let target = selectedTimeZone else {
            banner = Banner(kind: .error, text: String(localized: "Select a time zone first."))
            return
        }
        guard Timezones.isValid(target) else {
            banner = Banner(kind: .error, text: String(localized: "Not a valid IANA time zone: \(target)"))
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try store.setTimeZone(target)
            cliConfiguredTZ = target
            setDesktopMode(.fixed(target))
            banner = Banner(
                kind: .info,
                text: String(localized: "Saved env.TZ=\(target) for Claude Code and URL Handler. Restart those sessions to apply.")
            )
        } catch {
            banner = Banner(kind: .error, text: String(localized: "Could not update settings.json: \(String(describing: error))"))
        }
    }

    /// Removes only `env.TZ` and returns the Desktop target to system mode.
    func resetToSystemTimeZone() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try store.removeTimeZone()
            cliConfiguredTZ = nil
            selectedTimeZone = nil
            setDesktopMode(.system)
            banner = Banner(
                kind: .info,
                text: String(localized: "Removed env.TZ. Claude Code / URL Handler will use the system time zone after restart.")
            )
        } catch {
            banner = Banner(kind: .error, text: String(localized: "Could not update settings.json: \(String(describing: error))"))
        }
    }

    /// Adds or removes the sandbox rules that hide the Mac's time zone from
    /// Claude Code's commands and file tools.
    func setShield(_ on: Bool) {
        do {
            if on {
                let result = try store.enableTimeZoneShield()
                if result.enabledSandbox {
                    defaults.set(true, forKey: Self.shieldEnabledSandboxKey)
                }
                banner = Banner(
                    kind: .info,
                    text: String(localized: "Claude Code's sandbox now blocks reading the Mac's time zone. Restart sessions to apply.")
                )
            } else {
                try store.disableTimeZoneShield(disableSandbox: defaults.bool(forKey: Self.shieldEnabledSandboxKey))
                defaults.removeObject(forKey: Self.shieldEnabledSandboxKey)
                banner = Banner(kind: .info, text: String(localized: "Removed the sandbox rules that hide the Mac's time zone."))
            }
            shieldIsOn = on
        } catch {
            banner = Banner(kind: .error, text: String(localized: "Could not update settings.json: \(String(describing: error))"))
        }
    }

    /// Launches or relaunches Claude Desktop with the current Desktop target.
    func launchDesktop() async {
        guard let target = desktopTargetIdentifier else {
            banner = Banner(
                kind: .error,
                text: String(localized: "System time zone could not be resolved; cannot build a launch environment.")
            )
            return
        }
        isBusy = true
        defer { isBusy = false }
        let outcome = await desktop.activateOrLaunch(desired: target) {
            await Self.confirmTerminate(target: target)
        }
        switch outcome {
        case .activated:
            banner = Banner(kind: .info, text: String(localized: "Claude Desktop already runs with TZ=\(target); brought to front."))
        case .launched:
            banner = Banner(kind: .info, text: String(localized: "Launched Claude Desktop with TZ=\(target)."))
        case .cancelled:
            banner = nil
        case .relaunched:
            banner = Banner(kind: .info, text: String(localized: "Relaunched Claude Desktop with TZ=\(target)."))
        case .failed(let message):
            banner = Banner(kind: .error, text: String(localized: "Launch failed: \(message)"))
        }
        desktopStatus = desktop.status()
    }

    // MARK: - Desktop mode persistence

    private func setDesktopMode(_ mode: DesktopMode) {
        desktopMode = mode
        DesktopModePreference.store(mode, in: defaults)
        Task { await syncLauncher() }
    }

    // MARK: - Confirmation

    private static func confirmTerminate(target: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = String(localized: "Relaunch Claude Desktop?")
            alert.informativeText = String(
                localized: "Claude Desktop is running with a different or unknown time zone. CTimeZone will ask it to quit gracefully, then relaunch it with TZ=\(target). Unsaved work in Claude may be affected."
            )
            alert.addButton(withTitle: String(localized: "Relaunch"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.alertStyle = .warning
            continuation.resume(returning: alert.runModal() == .alertFirstButtonReturn)
        }
    }

    // MARK: - Dock launcher

    var canInstallLauncher: Bool { launcher != nil }

    var launcherName: String { LauncherInstaller.displayName(for: desktopMode) }

    func installLauncher() async {
        guard launcher != nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let url = try await writeLauncher()
            banner = Banner(
                kind: .info,
                text: String(localized: "Drag \u{201C}\(launcherName)\u{201D} from Finder to the Dock. Spotlight and Raycast find it too.")
            )
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            banner = Banner(kind: .error, text: String(localized: "Could not create the launcher: \(error.localizedDescription)"))
        }
    }

    func removeLauncher() {
        guard let url = launcherURL, let launcher else { return }
        do {
            try launcher.remove(url)
            launcherURL = nil
            defaults.removeObject(forKey: Self.launcherPathKey)
            banner = Banner(kind: .info, text: String(localized: "Moved the launcher to the Trash."))
        } catch {
            banner = Banner(kind: .error, text: String(localized: "Could not remove the launcher: \(error.localizedDescription)"))
        }
    }

    func revealLauncher() {
        guard let url = launcherURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Renames or refreshes an installed launcher after a zone change or an
    /// app update. Never creates one the user did not ask for.
    private func syncLauncher() async {
        guard let url = launcherURL, let launcher, !launcher.isCurrent(url, for: desktopMode) else { return }
        _ = try? await writeLauncher()
    }

    private func writeLauncher() async throws -> URL {
        guard let launcher else { throw CocoaError(.fileNoSuchFile) }
        let mode = desktopMode
        let existing = launcherURL
        let badge = NSApp.applicationIconImage ?? NSImage()
        let icon = LauncherInstaller.badgedClaudeIcon(badge: badge)
        // ditto and codesign block for a moment; keep them off the main thread.
        let url = try await Task.detached {
            try launcher.install(mode: mode, existing: existing, icon: icon)
        }.value
        launcherURL = url
        defaults.set(url.path, forKey: Self.launcherPathKey)
        return url
    }
}
