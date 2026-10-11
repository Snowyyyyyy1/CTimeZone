import Foundation

/// Validation and catalog helpers for IANA time zone identifiers.
///
/// We validate with `TimeZone(identifier:)` rather than
/// `TimeZone.knownTimeZoneIdentifiers`, because the known list omits valid
/// fixed-offset zones such as `UTC` and `Etc/GMT+5`.
public enum Timezones {
    public static func isValid(_ identifier: String) -> Bool {
        !identifier.isEmpty && TimeZone(identifier: identifier) != nil
    }

    /// Sorted catalog for the picker. Includes `UTC` and the known identifiers.
    public static func catalog() -> [String] {
        var ids = Set(TimeZone.knownTimeZoneIdentifiers)
        ids.insert("UTC")
        return ids.sorted()
    }

    /// City names in `locale`, keyed by identifier: "America/New_York" -> "纽约".
    /// Uses ICU's exemplar city; zones without one, such as `UTC`, keep the
    /// last identifier component.
    public static func cityNames(for zones: [String], locale: Locale) -> [String: String] {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "VVV"
        formatter.timeZone = TimeZone(identifier: "GMT")
        let unknown = formatter.string(from: .now)
        var names: [String: String] = [:]
        for zone in zones {
            let fallback = LauncherInstaller.city(of: zone)
            guard let timeZone = TimeZone(identifier: zone) else {
                names[zone] = fallback
                continue
            }
            formatter.timeZone = timeZone
            let city = formatter.string(from: .now)
            names[zone] = city == unknown ? fallback : city
        }
        return names
    }
}

/// The macOS system time zone, resolved independently of the current process
/// environment so an inherited `TZ` cannot distort it.
public struct SystemTimeZoneInfo: Equatable {
    public enum Source: Equatable {
        /// Resolved from the `/etc/localtime` symlink.
        case systemLink
        /// The link could not be resolved; fell back to the process time zone.
        case processFallback
        /// Neither the link nor the process time zone could be resolved.
        case unknown
    }

    public let identifier: String?
    public let source: Source

    public var isAuthoritative: Bool { source == .systemLink }
}

public enum SystemTimeZoneResolver {
    /// Reads the zoneinfo target of the `/etc/localtime` symlink.
    ///
    /// A symlink such as `/var/db/timezone/zoneinfo/Asia/Shanghai` yields
    /// `Asia/Shanghai`; nested zones such as
    /// `/var/db/timezone/zoneinfo/America/Argentina/Buenos_Aires` are preserved.
    /// If the link cannot be resolved or validated, we fall back to the current
    /// process time zone (explicitly labeled) and finally to `unknown`.
    public static func resolve(
        linkPath: String = "/etc/localtime",
        processIdentifier: String? = TimeZone.current.identifier
    ) -> SystemTimeZoneInfo {
        if let identifier = zoneinfoIdentifier(fromLinkAtPath: linkPath),
           Timezones.isValid(identifier) {
            return SystemTimeZoneInfo(identifier: identifier, source: .systemLink)
        }
        if let processIdentifier, Timezones.isValid(processIdentifier) {
            return SystemTimeZoneInfo(identifier: processIdentifier, source: .processFallback)
        }
        return SystemTimeZoneInfo(identifier: nil, source: .unknown)
    }

    /// Extracts the identifier after the last `/zoneinfo/` component.
    static func zoneinfoIdentifier(fromLinkAtPath path: String) -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else {
            return nil
        }
        guard let range = target.range(of: "/zoneinfo/", options: .backwards) else {
            return nil
        }
        let suffix = String(target[range.upperBound...])
        return suffix.isEmpty ? nil : suffix
    }
}
