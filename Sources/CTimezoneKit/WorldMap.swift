import Foundation

/// Equirectangular land mask for the dot-matrix world map.
///
/// Rasterized from Natural Earth 110m land (public domain) at 2° per cell,
/// latitudes 84°N to 60°S (Antarctica cropped). One bit per cell, row-major,
/// row 0 at the north edge.
public enum LandMask {
    public static let columns = 180
    public static let rows = 72
    public static let step = 2.0
    public static let northLatitude = 84.0
    public static let southLatitude = -60.0

    private static let bits: [UInt8] = Array(Data(base64Encoded: encoded) ?? Data())

    public static func isLand(column: Int, row: Int) -> Bool {
        guard (0..<columns).contains(column), (0..<rows).contains(row) else { return false }
        let index = row * columns + column
        guard index / 8 < bits.count else { return false }
        return bits[index / 8] & (0x80 >> UInt8(index % 8)) != 0
    }

    /// Center of a cell in degrees.
    public static func coordinate(column: Int, row: Int) -> (latitude: Double, longitude: Double) {
        (northLatitude - (Double(row) + 0.5) * step, -180 + (Double(column) + 0.5) * step)
    }

    private static let encoded =
        "AAAAAAAAf4AP/AAAAAAAAAAAAAAAAAAAAAAAAX/z///+AAAAAAAABAAAAAAAAAAAAAYd8P///wAA+AAAAAA8AAAAAAAAAAAwAnw////4AAIAAAAAAGAAAAAAAAAAADivwAf//wAAAAADAAf/wAHYAAAAAADoi3sAP//gAAAAAMAD///sAAAAgBgACfwz/AD/+gAAAwAEHf///+/8gBAP/7/nJdjwD/+AAAH/AA7f///////f4P//////h8H/gAAAf/6//f////////Mf/////9H4D8AeAA+ev///////////AP/////4A0B4AAAD5/////////////Af3////gHgA4AAAH5///////////LwAHgH///gHkAAAAAH4/////////+CIAABAB///4D+AAAAGCx/////////4A8AAIAAf///n/gAAAOCD/////////wA4AAAAAf///n/wAAAbP///////////AgAAAAAP/////wAAADf//////////9AAAAAAAF////0YAAAB///////////9AAAAAAAD////8EAAAB///////////5AAAAAAAD////2AAAAB/f5f///////wAAAAAAAD////gAAAAfxnwP///////jAAAAAAAD////AAAAAPCb3///////+CAAAAAAAD///8AAAAAfALf//////+ECAAAAAAAB///8AAAAAGHQP///////mMAAAAAAAA///8AAAAAH+Ai///////E8AAAAAAAAf//wAAAAAP/AA///////BgAAAAAAAAP//gAAAAAf/73///////gAAAAAAAAAD/AQAAAAAf////f/////gAAAAAAAAAF+AQAAAAB///+/n/////AAAAAAAAAAC+AAAAAAB///+f0H////AAAAAAAAAAAeAwAAAAD////f/B///8gAAAAAAAAAAeGEAAAAH////v+B/z/AAAAAAAAAAAAPMAgAAAD////n+A/B+gAAAAAAAAAAAD8AAAAAD////n4AeB/AgAAAAAAAAAAAPAAAAAH////3gAcAfAgAAAAAAAAAAADAAAAAD////6AAcAfggAAAAAAAAAAABDwAAAD////8wAMATAIAAAAAAAAAAAAr/AAAB/////gAKASAAAAAAAAAAAAAAH/gAAA/////gACAAAIAAAAAAAAAAAAH/8AAAaH///AAAAsGAAAAAAAAAAAAAH/+AAAAB//+AAAAUOAAAAAAAAAAAAAP/+AAAAB//8AAAAYegAAAAAAAAAAAAP//gAAAD//4AAAAMeBgAAAAAAAAAAAP//8AAAB//wAAAAGdiuAAAAAAAAAAAf///AAAA//wAAAACAQHgAAAAAAAAAAP///gAAA//wAAAABwAHwgAAAAAAAAAH///AAAA//wAAAAACIDQIAAAAAAAAAH//+AAAAf/wAAAAAAAAAAAAAAAAAAAD//+AAAA//wgAAAAABxAAAAAAAAAAAD//+AAAA//wgAAAAAPxgBAAAAAAAAAA//8AAAA//jgAAAAAf5gAAAAAAAAAAAf/8AAAA//DgAAAAAf/gAAAAAAAAAAAf/8AAAAf/DAAAAAD//4CAAAAAAAAAAf/wAAAAf/DAAAAAH//4AAAAAAAAAAAf/AAAAAf+CAAAAAH//8AAAAAAAAAAAf/AAAAAP8AAAAAAH//+AAAAAAAAAAA/+AAAAAP8AAAAAAH//+AAAAAAAAAAA/+AAAAAH4AAAAAAD//+AAAAAAAAAAA/8AAAAAHwAAAAAADwf8AAAAAAAAAAA/gAAAAAAAAAAAAACAH4AIAAAAAAAAB/wAAAAAAAAAAAAAAAD4AEAAAAAAAAB+AAAAAAAAAAAAAAAAAAAGAAAAAAAAB6AAAAAAAAAAAAAAAAAwAMAAAAAAAAA8AAAAAAAAAAAAAAAAAQAYAAAAAAAAB4AAAAAAAAAAAAAAAAAAAwAAAAAAAAB4AAAAAAAAAAAAAAAAAAAAAAAAAAAADwAAAAAAAAAACAAAAAAAAAAAAAAAAADgAAAAAAAAAAAAAAAAAAAAAAAAAAAABwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
}

public struct GeoPoint: Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Representative coordinates for IANA zones, read from the system's
/// `zone.tab`. Zones without an entry (UTC, Etc/*, legacy aliases) map to nil.
public enum ZoneLocations {
    public static func load(path: String = "/usr/share/zoneinfo/zone.tab") -> [String: GeoPoint] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        return parse(text)
    }

    static func parse(_ text: String) -> [String: GeoPoint] {
        var result: [String: GeoPoint] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, let point = parseISO6709(String(fields[1])) else { continue }
            result[String(fields[2])] = point
        }
        return result
    }

    /// Parses `±DDMM±DDDMM` or `±DDMMSS±DDDMMSS`.
    static func parseISO6709(_ value: String) -> GeoPoint? {
        let chars = Array(value)
        guard let split = chars.indices.dropFirst().first(where: { chars[$0] == "+" || chars[$0] == "-" }),
              let lat = degrees(String(chars[..<split]), degreeDigits: 2),
              let lon = degrees(String(chars[split...]), degreeDigits: 3)
        else { return nil }
        return GeoPoint(latitude: lat, longitude: lon)
    }

    private static func degrees(_ part: String, degreeDigits: Int) -> Double? {
        guard let sign = part.first, sign == "+" || sign == "-" else { return nil }
        let digits = Array(part.dropFirst())
        guard digits.count == degreeDigits + 2 || digits.count == degreeDigits + 4,
              digits.allSatisfy(\.isNumber) else { return nil }
        func number(_ range: Range<Int>) -> Double { Double(String(digits[range]))! }
        var value = number(0..<degreeDigits) + number(degreeDigits..<degreeDigits + 2) / 60
        if digits.count == degreeDigits + 4 {
            value += number(degreeDigits + 2..<degreeDigits + 4) / 3600
        }
        return sign == "-" ? -value : value
    }
}

/// Low-precision solar position, accurate to well under a degree, which is
/// plenty for shading day and night on a 2° grid.
public enum SolarPosition {
    /// The point on Earth where the sun is directly overhead at `date`.
    public static func subsolarPoint(at date: Date) -> GeoPoint {
        let days = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0
        let rad = Double.pi / 180
        let meanLongitude = (280.460 + 0.9856474 * days).truncatingRemainder(dividingBy: 360)
        let anomaly = (357.528 + 0.9856003 * days).truncatingRemainder(dividingBy: 360) * rad
        let eclipticLongitude = (meanLongitude + 1.915 * sin(anomaly) + 0.020 * sin(2 * anomaly)) * rad
        let obliquity = (23.439 - 0.0000004 * days) * rad
        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))
        let gmst = (280.46061837 + 360.98564736629 * days).truncatingRemainder(dividingBy: 360)
        var longitude = rightAscension / rad - gmst
        longitude = (longitude + 540).truncatingRemainder(dividingBy: 360) - 180
        return GeoPoint(latitude: declination / rad, longitude: longitude)
    }

    /// Cosine of the solar zenith angle at `point`: > 0 is day, < 0 is night.
    public static func daylight(at point: GeoPoint, sun: GeoPoint) -> Double {
        let rad = Double.pi / 180
        let lat = point.latitude * rad, dec = sun.latitude * rad
        return sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos((point.longitude - sun.longitude) * rad)
    }
}
