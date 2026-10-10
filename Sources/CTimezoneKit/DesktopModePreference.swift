import Foundation

/// Which time zone CTimezone uses for the Claude Desktop launch environment.
public enum DesktopMode: Equatable {
    /// Follow the resolved macOS system time zone.
    case system
    /// Use an explicit IANA identifier.
    case fixed(String)

    public var identifier: String? {
        if case .fixed(let tz) = self { return tz }
        return nil
    }
}

/// Persists the Desktop mode in `UserDefaults` under a single key.
///
/// The stored value is either the explicit `system` sentinel or an IANA id.
/// Absence is distinct from an explicit `system` preference.
public enum DesktopModePreference {
    public static let key = "desktopTZMode"
    public static let systemSentinel = "__system__"

    /// Loads the stored mode.
    ///
    /// - An explicitly stored preference always wins, including the explicit
    ///   System sentinel (so Reset/relaunch stays System).
    /// - Only when the key is truly unset do we seed from a valid
    ///   `configuredTZ` (the existing `settings.env.TZ`), avoiding a silent
    ///   System default for a user whose shared config is already set.
    public static func load(_ defaults: UserDefaults, configuredTZ: String?) -> DesktopMode {
        if defaults.object(forKey: key) != nil,
           let raw = defaults.string(forKey: key) {
            return raw == systemSentinel ? .system : .fixed(raw)
        }
        if let configuredTZ, Timezones.isValid(configuredTZ) {
            return .fixed(configuredTZ)
        }
        return .system
    }

    public static func store(_ mode: DesktopMode, in defaults: UserDefaults) {
        switch mode {
        case .system: defaults.set(systemSentinel, forKey: key)
        case .fixed(let tz): defaults.set(tz, forKey: key)
        }
    }
}
