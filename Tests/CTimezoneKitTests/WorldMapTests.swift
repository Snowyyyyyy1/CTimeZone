@testable import CTimezoneKit
import XCTest

final class WorldMapTests: XCTestCase {
    func testParsesMinuteAndSecondPrecision() {
        let shanghai = ZoneLocations.parseISO6709("+3114+12128")
        XCTAssertEqual(shanghai?.latitude ?? 0, 31.2333, accuracy: 0.001)
        XCTAssertEqual(shanghai?.longitude ?? 0, 121.4667, accuracy: 0.001)

        let newYork = ZoneLocations.parseISO6709("+404251-0740023")
        XCTAssertEqual(newYork?.latitude ?? 0, 40.7142, accuracy: 0.001)
        XCTAssertEqual(newYork?.longitude ?? 0, -74.0064, accuracy: 0.001)

        XCTAssertNil(ZoneLocations.parseISO6709("garbage"))
    }

    func testParseSkipsCommentsAndKeepsZoneNames() {
        let table = "# comment\nNL\t+5222+00454\tEurope/Amsterdam\nAU\t-3352+15113\tAustralia/Sydney\tNSW\n"
        let parsed = ZoneLocations.parse(table)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed["Australia/Sydney"]?.latitude ?? 0, -33.8667, accuracy: 0.001)
    }

    func testLandMaskKnownCells() {
        func land(_ lat: Double, _ lon: Double) -> Bool {
            let row = Int((LandMask.northLatitude - lat) / LandMask.step)
            let column = Int((lon + 180) / LandMask.step)
            return LandMask.isLand(column: column, row: row)
        }
        XCTAssertTrue(land(48.9, 2.3))     // Paris
        XCTAssertTrue(land(-23.5, 133.0))  // Central Australia
        XCTAssertFalse(land(0.0, -140.0))  // Pacific
        XCTAssertFalse(land(30.0, -40.0))  // Atlantic
    }

    func testSubsolarPointNearEquinoxNoon() {
        // 2024-03-20 12:00 UTC: sun near the equator, close to Greenwich.
        let date = ISO8601DateFormatter().date(from: "2024-03-20T12:00:00Z")!
        let sun = SolarPosition.subsolarPoint(at: date)
        XCTAssertEqual(sun.latitude, 0, accuracy: 1)
        XCTAssertEqual(sun.longitude, 0, accuracy: 3)
    }

    func testDaylightFollowsTheSeasons() {
        func light(_ iso: String, latitude: Double, longitude: Double) -> Double {
            let date = ISO8601DateFormatter().date(from: iso)!
            return SolarPosition.daylight(
                at: GeoPoint(latitude: latitude, longitude: longitude),
                sun: SolarPosition.subsolarPoint(at: date)
            )
        }
        // Midnight sun in the Arctic in June, polar night in December, at
        // every hour, while the Antarctic has the opposite.
        for hour in stride(from: 0, to: 24, by: 6) {
            let h = String(format: "%02d", hour)
            XCTAssertGreaterThan(light("2024-06-21T\(h):00:00Z", latitude: 80, longitude: 0), 0)
            XCTAssertLessThan(light("2024-12-21T\(h):00:00Z", latitude: 80, longitude: 0), 0)
            XCTAssertLessThan(light("2024-06-21T\(h):00:00Z", latitude: -80, longitude: 0), 0)
            XCTAssertGreaterThan(light("2024-12-21T\(h):00:00Z", latitude: -80, longitude: 0), 0)
        }
    }

    func testSubsolarLatitudeTracksSolstices() {
        let june = SolarPosition.subsolarPoint(at: ISO8601DateFormatter().date(from: "2024-06-20T21:00:00Z")!)
        let december = SolarPosition.subsolarPoint(at: ISO8601DateFormatter().date(from: "2024-12-21T09:00:00Z")!)
        XCTAssertEqual(june.latitude, 23.44, accuracy: 0.5)
        XCTAssertEqual(december.latitude, -23.44, accuracy: 0.5)
    }
}
