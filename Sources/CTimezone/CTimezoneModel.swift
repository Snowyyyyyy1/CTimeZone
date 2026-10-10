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
    private(set) var systemZone: SystemTimeZoneInfo
    private(set) var desktopMode: DesktopMode
    private(set) var desktopStatus: ClaudeDesktopController.Status

    let catalog: [String]
    let locations: [String: GeoPoint]

    private let store: ClaudeSettingsStore
    private let desktop: ClaudeDesktopController
    private let defaults: UserDefaults

    init(
        store: ClaudeSettingsStore = ClaudeSettingsStore(),
        desktop: ClaudeDesktopController = ClaudeDesktopController(),
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.desktop = desktop
        self.defaults = defaults
        self.catalog = Timezones.catalog()
        self.locations = ZoneLocations.load()
        self.systemZone = SystemTimeZoneResolver.resolve()

        let configured = try? store.currentTimeZone()
        self.cliConfiguredTZ = configured ?? nil
        self.selectedTimeZone = configured ?? nil
        self.desktopMode = DesktopModePreference.load(defaults, configuredTZ: configured ?? nil)
        self.desktopStatus = desktop.status()
    }

    var filteredCatalog: [String] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return catalog }
        // Match "new york" against "America/New_York".
        let normalized = query.replacingOccurrences(of: " ", with: "_")
        return catalog.filter { $0.localizedCaseInsensitiveContains(normalized) }
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
        case .system: return "System (\(systemZone.identifier ?? "unknown"))"
        case .fixed(let tz): return tz
        }
    }

    func refresh() {
        systemZone = SystemTimeZoneResolver.resolve()
        // Keep the last known value only when the file is unreadable; an absent
        // key must clear it so external removals show up.
        do { cliConfiguredTZ = try store.currentTimeZone() } catch {}
        desktopStatus = desktop.status()
    }

    /// Writes `env.TZ` in settings.json and records the Desktop target.
    /// Does not touch the running Desktop process.
    func apply() async {
        guard let target = selectedTimeZone else {
            banner = Banner(kind: .error, text: "Select a time zone first.")
            return
        }
        guard Timezones.isValid(target) else {
            banner = Banner(kind: .error, text: "Not a valid IANA time zone: \(target)")
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
                text: "Saved env.TZ=\(target) for Claude Code and URL Handler. Restart those sessions to apply."
            )
        } catch {
            banner = Banner(kind: .error, text: "Could not update settings.json: \(error)")
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
                text: "Removed env.TZ. Claude Code / URL Handler will use the system time zone after restart."
            )
        } catch {
            banner = Banner(kind: .error, text: "Could not update settings.json: \(error)")
        }
    }

    /// Launches or relaunches Claude Desktop with the current Desktop target.
    func launchDesktop() async {
        guard let target = desktopTargetIdentifier else {
            banner = Banner(
                kind: .error,
                text: "System time zone could not be resolved; cannot build a launch environment."
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
            banner = Banner(kind: .info, text: "Claude Desktop already runs with TZ=\(target); brought to front.")
        case .launched:
            banner = Banner(kind: .info, text: "Launched Claude Desktop with TZ=\(target).")
        case .cancelled:
            banner = nil
        case .relaunched:
            banner = Banner(kind: .info, text: "Relaunched Claude Desktop with TZ=\(target).")
        case .failed(let message):
            banner = Banner(kind: .error, text: "Launch failed: \(message)")
        }
        desktopStatus = desktop.status()
    }

    // MARK: - Desktop mode persistence

    private func setDesktopMode(_ mode: DesktopMode) {
        desktopMode = mode
        DesktopModePreference.store(mode, in: defaults)
    }

    // MARK: - Confirmation

    private static func confirmTerminate(target: String) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Relaunch Claude Desktop?"
            alert.informativeText =
                "Claude Desktop is running with a different or unknown time zone. "
                + "CTimeZone will ask it to quit gracefully, then relaunch it with TZ=\(target). "
                + "Unsaved work in Claude may be affected."
            alert.addButton(withTitle: "Relaunch")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            continuation.resume(returning: alert.runModal() == .alertFirstButtonReturn)
        }
    }
}
