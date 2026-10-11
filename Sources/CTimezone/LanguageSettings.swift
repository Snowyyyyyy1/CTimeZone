import AppKit
import CTimezoneKit
import SwiftUI

/// Applies the interface language to CTimeZone and its Dock launchers.
@MainActor
enum LanguageSettings {
    /// Installed launchers share this domain. Neither app is sandboxed, so
    /// CTimeZone can write it, and macOS reads it when a launcher starts.
    static let launcherDomain = "com.snowyy.CTimezone.ClaudeLauncher"

    /// The language this process started with. Read once at launch, because
    /// the running app keeps using it until it relaunches.
    static let launched = current

    static var current: AppLanguage {
        AppLanguage(domain: Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:)))
    }

    static func apply(_ language: AppLanguage) {
        language.store(in: .standard)
        syncLauncher(language)
    }

    /// Also covers a language picked in System Settings, once CTimeZone opens.
    static func syncLauncher(_ language: AppLanguage? = nil) {
        guard let defaults = UserDefaults(suiteName: launcherDomain) else { return }
        (language ?? current).store(in: defaults)
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

struct LanguageSettingsView: View {
    @State private var selection = LanguageSettings.current

    var body: some View {
        Form {
            Section {
                Picker("Language", selection: $selection) {
                    Text("Follow System").tag(AppLanguage.system)
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "简体中文").tag(AppLanguage.simplifiedChinese)
                }
                .onChange(of: selection) { _, language in
                    LanguageSettings.apply(language)
                }
                .accessibilityIdentifier("ctz.languagePicker")

                if selection != LanguageSettings.launched {
                    HStack {
                        Text("Restart CTimeZone to use the new language.")
                        Spacer(minLength: 8)
                        Button("Restart Now") { LanguageSettings.relaunch() }
                            .accessibilityIdentifier("ctz.restartButton")
                    }
                }
            } footer: {
                Text("The Dock launcher follows this setting too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
