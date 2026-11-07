import XCTest
@testable import AstikaKastorias

/// Checks against the network built into the app
final class TransitDataTests: XCTestCase {
    private var data: TransitData!
    private var schedule: Schedule!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: AppContainer.self).url(forResource: "transit", withExtension: "json"))
        let bundle = try JSONDecoder().decode(TransitBundle.self, from: Data(contentsOf: url))
        XCTAssertEqual(bundle.schema, TransitBundle.currentSchema)
        XCTAssertTrue(bundle.isUsable)
        data = TransitData(bundle)
        schedule = Schedule(data)
    }

    func testTerminalHasDepartures() {
        // A weekday morning at the Αφετηρία
        let now = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 9), hour: 8, minute: 0)
        let departures = schedule.nextDepartures("16001", now: now, limit: 5)
        XCTAssertFalse(departures.isEmpty)
        XCTAssertTrue(departures.allSatisfy { $0.minutes >= 480 || $0.dayOffset == 1 })
        XCTAssertEqual(departures.map(\.minutes), departures.map(\.minutes).sorted())
    }

    func testHolidaysRunOnSunday() {
        XCTAssertEqual(schedule.serviceDay(for: LocalDate(year: 2026, month: 3, day: 25)), .sunday)
        XCTAssertEqual(schedule.serviceDay(for: LocalDate(year: 2026, month: 4, day: 13)), .sunday)
        XCTAssertEqual(schedule.serviceDay(for: LocalDate(year: 2026, month: 11, day: 9)), .weekday)
    }

    func testEstimatedBusesAreOnTheMap() {
        let now = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 9), hour: 10, minute: 30)
        let buses = BusEstimator(data: data, schedule: schedule).estimate(now)
        XCTAssertFalse(buses.isEmpty)
        for bus in buses {
            XCTAssertEqual(bus.lat, 40.5, accuracy: 0.2)
            XCTAssertEqual(bus.lng, 21.25, accuracy: 0.2)
        }
    }

    func testJourneyFromTheUniversityToTheCentre() throws {
        let university = try XCTUnwrap(data.stop("16114"))
        let now = LocalDateTime(date: LocalDate(year: 2026, month: 11, day: 9), hour: 9, minute: 0)
        let plan = try XCTUnwrap(JourneyPlanner.plan(data: data, schedule: schedule, destination: .centre,
                                                     lat: university.lat, lng: university.lng, now: now))
        XCTAssertNotEqual(plan.status, .tooFar)
        XCTAssertNotEqual(plan.status, .alreadyThere)
    }

    func testFarAwayIsTooFar() throws {
        let plan = try XCTUnwrap(JourneyPlanner.plan(data: data, schedule: schedule, destination: .centre,
                                                     lat: 37.98, lng: 23.73, now: .now))
        XCTAssertEqual(plan.status, .tooFar)
    }

    func testLiveBusOnItsTripGetsADelay() throws {
        // A bus of the first line with a timetable, halfway between its second and third stops, a minute late
        let line = try XCTUnwrap(data.lines.first { l in l.directions.contains { d in !schedule.departures(l.id, d.id, on: LocalDate(year: 2026, month: 11, day: 9)).isEmpty } })
        let direction = try XCTUnwrap(line.directions.first { !schedule.departures(line.id, $0.id, on: LocalDate(year: 2026, month: 11, day: 9)).isEmpty })
        let start = try XCTUnwrap(schedule.departures(line.id, direction.id, on: LocalDate(year: 2026, month: 11, day: 9)).first)
        let a = try XCTUnwrap(data.stop(direction.stops[1].stop))
        let b = try XCTUnwrap(data.stop(direction.stops[2].stop))
        let offset = Double(direction.stops[1].offset) + Double(direction.stops[2].offset - direction.stops[1].offset) / 2
        let seen = Double(start) + offset + 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Athens")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: Int(seen) / 60, minute: Int(seen) % 60,
                                                      second: Int((seen - floor(seen)) * 60)))!
        let formatter = ISO8601DateFormatter()
        let bus = LiveBus(vehicle: "1", line: line.id, direction: direction.id, lat: (a.lat + b.lat) / 2, lng: (a.lng + b.lng) / 2,
                          bearing: nil, speed: nil, t: formatter.string(from: date))
        let trips = LiveTrips.compute(data: data, schedule: schedule, buses: [bus], calendar: calendar)
        XCTAssertEqual(trips.count, 1)
        XCTAssertEqual(trips.first?.tripStart, start)
        XCTAssertEqual(Double(trips.first?.delay ?? 99), 1, accuracy: 1)
    }
}
