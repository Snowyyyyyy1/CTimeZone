import SwiftUI

@main
struct CTimezoneApp: App {
    @StateObject private var updater = UpdaterService.shared

    init() {
        _ = LanguageSettings.launched
        LanguageSettings.syncLauncher()
    }

    var body: some Scene {
        Window("CTimeZone", id: "main") {
            CTimezoneView()
        }
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates\u{2026}") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
                    .help(updater.availability.reason ?? "")
            }
        }

        Settings {
            LanguageSettingsView()
        }
    }
}
