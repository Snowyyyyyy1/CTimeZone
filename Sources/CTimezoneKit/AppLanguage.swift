import Foundation

/// Interface language chosen in CTimeZone.
///
/// Stored as `AppleLanguages` in an app's own preferences domain, the same key
/// the per-app language setting in System Settings writes. macOS reads it at
/// launch, so a change takes effect after a relaunch. Absent means the app
/// follows the system language.
public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public static let key = "AppleLanguages"

    public var id: String { rawValue }

    /// `domain` must be the app's persistent domain only. Reading through
    /// `UserDefaults` would also return the system-wide list, which is not a
    /// choice the user made for this app.
    public init(domain: [String: Any]?) {
        let first = (domain?[Self.key] as? [String])?.first ?? ""
        self = Self.allCases.first { $0 != .system && first.hasPrefix($0.rawValue) } ?? .system
    }

    public func store(in defaults: UserDefaults) {
        if self == .system {
            defaults.removeObject(forKey: Self.key)
        } else {
            defaults.set([rawValue], forKey: Self.key)
        }
    }
}
