import XCTest
@testable import AstikaKastorias

final class ScheduleTests: XCTestCase {
    func testOrthodoxEaster() {
        XCTAssertEqual(Schedule.orthodoxEaster(2024), LocalDate(year: 2024, month: 5, day: 5))
        XCTAssertEqual(Schedule.orthodoxEaster(2025), LocalDate(year: 2025, month: 4, day: 20))
        XCTAssertEqual(Schedule.orthodoxEaster(2026), LocalDate(year: 2026, month: 4, day: 12))
    }

    func testMovableHolidays2026() {
        // Clean Monday, Good Friday, Easter Monday, Holy Spirit Monday
        XCTAssertEqual(Schedule.movableHolidays(2026), ["02-23", "04-10", "04-13", "06-01"])
    }

    func testTimes() {
        XCTAssertEqual(Schedule.toMinutes("07:05"), 425)
        XCTAssertEqual(Schedule.toMinutes("bad"), nil)
        XCTAssertEqual(Schedule.formatMinutes(425), "07:05")
        XCTAssertEqual(Schedule.formatMinutes(1450), "00:10")
    }

    func testDates() {
        let date = LocalDate(year: 2026, month: 11, day: 7)
        XCTAssertTrue(date.isSaturday)
        XCTAssertEqual(date.plusDays(1).weekday, 1)
        XCTAssertEqual(LocalDate(year: 2026, month: 12, day: 31).plusDays(1), LocalDate(year: 2027, month: 1, day: 1))
        XCTAssertEqual(date.mmdd, "11-07")
        XCTAssertEqual(LocalDate(iso: "2026-03-25"), LocalDate(year: 2026, month: 3, day: 25))
    }

    func testPolyline() {
        // Google's own example
        let points = Geo.decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].lat, 38.5, accuracy: 1e-6)
        XCTAssertEqual(points[0].lng, -120.2, accuracy: 1e-6)
        XCTAssertEqual(points[2].lat, 43.252, accuracy: 1e-6)
        XCTAssertEqual(points[2].lng, -126.453, accuracy: 1e-6)
    }

    func testDistances() {
        XCTAssertEqual(Geo.formatDistance(243, language: "el"), "240 μ.")
        XCTAssertEqual(Geo.formatDistance(1430, language: "el"), "1,4 χλμ.")
        XCTAssertEqual(Geo.formatDistance(1430, language: "en"), "1.4 km")
    }

    func testPlaceholders() {
        XCTAssertEqual(Strings.fill("%1$d:%2$02d", [7, 5]), "7:05")
        XCTAssertEqual(Strings.fill("to %1$s", ["Πανεπιστήμιο"]), "to Πανεπιστήμιο")
        XCTAssertEqual(Strings.fill("%1$s to %2$s", ["07:00", "20:15"]), "07:00 to 20:15")
    }

    func testSmoothTimes() {
        // Three stops in the same minute get times spread by distance
        let seconds = BusEstimator.smoothTimes([0, 1, 1, 1, 3], [0, 100, 200, 300, 400])
        XCTAssertEqual(seconds[0], 0)
        XCTAssertEqual(seconds[1], 60)
        XCTAssertEqual(seconds[2], 60 + 120 * (100.0 / 300))
        XCTAssertEqual(seconds[4], 180)
    }
}
