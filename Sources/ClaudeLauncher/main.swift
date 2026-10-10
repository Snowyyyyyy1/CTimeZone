import AppKit
import CTimezoneKit

/// Opens Claude Desktop in the zone chosen in CTimeZone, then quits.
///
/// The setting is read at click time, so a launcher that has not been renamed
/// yet still launches in the current zone.
@MainActor
enum Launcher {
    /// CTimeZone's preferences domain (its bundle identifier). Readable here
    /// because neither app is sandboxed.
    static let settingsDomain = "com.snowyy.CTimezone"

    static func run() async {
        let defaults = UserDefaults(suiteName: settingsDomain) ?? .standard
        let configured = (try? ClaudeSettingsStore().currentTimeZone()) ?? nil
        let mode = DesktopModePreference.load(defaults, configuredTZ: configured)

        guard FileManager.default.fileExists(atPath: ClaudeDesktopController.appPath) else {
            showError("Claude is not installed", "Install Claude Desktop in /Applications, then try again.")
            return
        }
        guard let target = mode.identifier ?? SystemTimeZoneResolver.resolve().identifier else {
            showError("Time zone unavailable", "Open CTimeZone and choose a time zone for Claude.")
            return
        }

        let controller = ClaudeDesktopController()
        let current = describe(controller.status().observedTZ)
        let outcome = await controller.activateOrLaunch(desired: target) {
            await confirmRelaunch(current: current, target: target)
        }
        switch outcome {
        case .launched, .relaunched, .activated:
            break
        case .cancelled:
            // "Just Open": the user still wants Claude, only without a restart.
            controller.activateRunning()
        case .failed(let message):
            showError("Could not open Claude", message)
        }
    }

    private static func describe(_ observed: ProcessTZProbe.Result) -> String {
        switch observed {
        case .value(let zone): return zone
        case .absent: return "the system time zone"
        case .unavailable: return "an unknown time zone"
        }
    }

    private static func confirmRelaunch(current: String, target: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Claude is running in \(current)"
        alert.informativeText = "Relaunch it in \(target)? Claude quits normally first; unsaved work in Claude may be affected."
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Just Open")
        // A windowless app must come forward or the alert opens behind everything.
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func showError(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    await Launcher.run()
    exit(0)
}
app.run()
