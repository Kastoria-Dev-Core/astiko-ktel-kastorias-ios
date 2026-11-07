import Foundation

/// Timetable logic: the kind of day, the season, holidays and Easter, and the next departures.
/// The same rules as the Android app's Schedule.kt.
final class Schedule {
    private let data: TransitData

    init(_ data: TransitData) {
        self.data = data
    }

    /// Stops a bus leaves from on at least one day. Leaves out stops that are only the last stop of a
    /// direction and stops served only by lines that have no timetable.
    lazy var departureStopIds: Set<String> = {
        var ids = Set<String>()
        for line in data.lines {
            for d in line.directions where data.timetables.contains(where: { $0.line == line.id && $0.direction == d.id && !$0.departures.isEmpty }) {
                for s in d.stops.dropLast() { ids.insert(s.stop) }
            }
        }
        return ids
    }()

    /// Holidays use the Sunday timetable
    func serviceDay(for date: LocalDate) -> ServiceDay {
        if isHoliday(date) || date.isSunday { return .sunday }
        if date.isSaturday { return .saturday }
        return .weekday
    }

    /// Summer between the `Meta.summer` dates, both included, winter the rest of the year
    func season(for date: LocalDate) -> Season {
        let key = date.mmdd
        let summer = data.meta.summer
        return key >= summer.from && key <= summer.to ? .summer : .winter
    }

    /// One of the fixed holidays in meta.json, or one that moves with Orthodox Easter
    func isHoliday(_ date: LocalDate) -> Bool {
        let key = date.mmdd
        return data.meta.holidays.contains(key) || Schedule.movableHolidays(date.year).contains(key)
    }

    /// Whether a line has its own Wednesday timetable, in either direction
    func hasWednesday(_ lineId: String) -> Bool {
        data.timetables.contains { $0.line == lineId && $0.service == .wednesday }
    }

    /// The timetable a line runs on a date: `serviceDay`, except on a Wednesday that isn't a holiday,
    /// when a line with a Wednesday timetable runs that one
    func timetableDay(_ lineId: String, _ date: LocalDate) -> ServiceDay {
        let day = serviceDay(for: date)
        if day == .weekday && date.isWednesday && hasWednesday(lineId) { return .wednesday }
        return day
    }

    /// Departures from the first stop, minutes since midnight, sorted. Falls back to the winter timetable,
    /// and from the Wednesday timetable to the weekday one.
    func departures(_ lineId: String, _ directionId: String, _ service: ServiceDay, _ season: Season) -> [Int] {
        (timetable(lineId, directionId, service, season)?.departures ?? []).compactMap(Schedule.toMinutes).sorted()
    }

    /// The operator's notes on the same departures, by minutes since midnight
    func notes(_ lineId: String, _ directionId: String, _ service: ServiceDay, _ season: Season) -> [Int: String] {
        var out: [Int: String] = [:]
        for (time, note) in timetable(lineId, directionId, service, season)?.notes ?? [:] {
            if let m = Schedule.toMinutes(time) { out[m] = note }
        }
        return out
    }

    private func timetable(_ lineId: String, _ directionId: String, _ service: ServiceDay, _ season: Season) -> Timetable? {
        let found = data.timetables.first { $0.line == lineId && $0.direction == directionId && $0.service == service && $0.season == season }
            ?? data.timetables.first { $0.line == lineId && $0.direction == directionId && $0.service == service && $0.season == .winter }
        if found == nil && service == .wednesday { return timetable(lineId, directionId, .weekday, season) }
        return found
    }

    /// Departures from the first stop on a date, from the timetable of that day and season
    func departures(_ lineId: String, _ directionId: String, on date: LocalDate) -> [Int] {
        departures(lineId, directionId, timetableDay(lineId, date), season(for: date))
    }

    /// Upcoming departures from a stop: the rest of today, then tomorrow's first ones. A trip in `live`
    /// gets its time from where the bus really is: later or earlier by its delay, and gone once the bus
    /// has passed the stop.
    func nextDepartures(_ stopId: String, now: LocalDateTime, limit: Int, live: [LiveTrip] = []) -> [Departure] {
        let nowMin = Schedule.minutesOfDay(now)
        let today = departuresAtStop(stopId, on: now.date, dayOffset: 0)
            .compactMap { dep -> Departure? in
                guard let trip = live.first(where: { $0.lineId == dep.line.id && $0.directionId == dep.direction.id && $0.tripStart == dep.tripStart }) else {
                    return dep.minutes >= nowMin ? dep : nil
                }
                if dep.stopIndex <= trip.passedIndex { return nil }
                // Due any moment: shown as "now" rather than dropped while the bus is still coming
                var moved = dep
                moved.minutes = max(dep.minutes + trip.delay, nowMin)
                moved.live = true
                return moved
            }
            .sorted { $0.minutes < $1.minutes }
        if today.count >= limit { return Array(today.prefix(limit)) }
        let tomorrow = departuresAtStop(stopId, on: now.date.plusDays(1), dayOffset: 1).sorted { $0.minutes < $1.minutes }
        return Array((today + tomorrow).prefix(limit))
    }

    /// The bus that left a stop most recently today, if any left in the last `withinMinutes`
    func previousDeparture(_ stopId: String, now: LocalDateTime, withinMinutes: Int = 30) -> Departure? {
        let nowMin = Schedule.minutesOfDay(now)
        return departuresAtStop(stopId, on: now.date, dayOffset: 0)
            .filter { $0.minutes < nowMin && $0.minutes >= nowMin - withinMinutes }
            .max { $0.minutes < $1.minutes }
    }

    /// When the next bus of a direction reaches each of its stops today, minutes since midnight, in stop
    /// order. nil for a stop no more buses reach today.
    func nextArrivals(_ line: Line, _ direction: Direction, now: LocalDateTime) -> [Int?] {
        let nowMin = Schedule.minutesOfDay(now)
        let deps = departures(line.id, direction.id, on: now.date)
        return direction.stops.map { s in deps.map { $0 + s.offset }.first { $0 >= nowMin } }
    }

    /// Where the buses on the road are along a direction right now, from the timetable, counted in stops
    /// from the first: 2.5 is halfway between the third and the fourth stop.
    func positionsOnRoute(_ line: Line, _ direction: Direction, now: LocalDateTime) -> [Double] {
        let offsets = direction.stops.map(\.offset)
        guard offsets.count >= 2, let total = offsets.last else { return [] }
        let nowMin = Double(now.secondOfDay) / 60.0
        return departures(line.id, direction.id, on: now.date).compactMap { dep in
            let elapsed = nowMin - Double(dep)
            if elapsed < 0 || elapsed >= Double(total) { return nil }
            // The last stretch that has started; stops in the same minute are passed together
            guard let i = offsets.indices.last(where: { $0 < offsets.count - 1 && Double(offsets[$0]) <= elapsed && offsets[$0 + 1] > offsets[$0] }) else {
                return nil
            }
            return Double(i) + (elapsed - Double(offsets[i])) / Double(offsets[i + 1] - offsets[i])
        }
    }

    /// Next departure of a direction from its first stop, today only
    func nextTrip(_ line: Line, _ direction: Direction, now: LocalDateTime) -> Int? {
        let nowMin = Schedule.minutesOfDay(now)
        return departures(line.id, direction.id, on: now.date).first { $0 >= nowMin }
    }

    /// All departures from a stop on a date. The last stop of a direction is skipped (buses arrive, they don't leave).
    private func departuresAtStop(_ stopId: String, on date: LocalDate, dayOffset: Int) -> [Departure] {
        let dateSeason = self.season(for: date)
        var out: [Departure] = []
        for line in data.lines {
            for direction in line.directions {
                guard let idx = direction.stops.firstIndex(where: { $0.stop == stopId }), idx != direction.stops.count - 1 else { continue }
                let offset = direction.stops[idx].offset
                let day = timetableDay(line.id, date)
                let deps = self.departures(line.id, direction.id, day, dateSeason)
                let tripNotes = self.notes(line.id, direction.id, day, dateSeason)
                for (i, dep) in deps.enumerated() {
                    out.append(Departure(
                        line: line, direction: direction, minutes: dep + offset, dayOffset: dayOffset,
                        last: i == deps.count - 1, note: tripNotes[dep], tripStart: dep, stopIndex: idx
                    ))
                }
            }
        }
        return out
    }

    // MARK: - Times and dates

    /// "HH:MM" to minutes since midnight
    static func toMinutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let h = parts[0], let m = parts[1] else { return nil }
        return h * 60 + m
    }

    /// Minutes since midnight to "HH:MM"; past midnight wraps round, so 1450 is "00:10"
    static func formatMinutes(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Minutes since midnight, seconds dropped
    static func minutesOfDay(_ t: LocalDateTime) -> Int { t.hour * 60 + t.minute }

    /// Minutes from now until a departure
    static func minutesUntil(_ dep: Departure, now: LocalDateTime) -> Int {
        dep.minutes + dep.dayOffset * 1440 - minutesOfDay(now)
    }

    /// Orthodox Easter Sunday (Gregorian date), valid 1900-2099
    static func orthodoxEaster(_ year: Int) -> LocalDate {
        let a = year % 4
        let b = year % 7
        let c = year % 19
        let d = (19 * c + 15) % 30
        let e = (2 * a + 4 * b - d + 34) % 7
        let month = (d + e + 114) / 31
        let day = ((d + e + 114) % 31) + 1
        return LocalDate(year: year, month: month, day: day).plusDays(13)
    }

    /// Clean Monday, Good Friday, Easter Monday, Holy Spirit Monday
    static func movableHolidays(_ year: Int) -> [String] {
        let easter = orthodoxEaster(year)
        return [-48, -2, 1, 50].map { easter.plusDays($0).mmdd }
    }
}
