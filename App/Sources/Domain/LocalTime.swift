import Foundation

/// A calendar date with no time or zone, like Java's LocalDate
struct LocalDate: Hashable, Comparable {
    /// The year, e.g. 2026
    let year: Int
    /// The month, 1 to 12
    let month: Int
    /// The day of the month, 1 to 31
    let day: Int

    /// Plain Gregorian arithmetic in UTC, so a summer time change never moves a date
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var noon: Date {
        LocalDate.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// 1 Sunday, 2 Monday, … 7 Saturday, like Calendar's weekday
    var weekday: Int { LocalDate.utc.component(.weekday, from: noon) }

    /// Sundays run on the Sunday timetable
    var isSunday: Bool { weekday == 1 }
    /// Some lines have their own Wednesday timetable
    var isWednesday: Bool { weekday == 4 }
    /// Saturdays run on the Saturday timetable
    var isSaturday: Bool { weekday == 7 }

    /// The date `days` later, or earlier when negative
    func plusDays(_ days: Int) -> LocalDate {
        let date = LocalDate.utc.date(byAdding: .day, value: days, to: noon)!
        let c = LocalDate.utc.dateComponents([.year, .month, .day], from: date)
        return LocalDate(year: c.year!, month: c.month!, day: c.day!)
    }

    /// "MM-DD", how meta.json writes holidays and seasons
    var mmdd: String { String(format: "%02d-%02d", month, day) }

    /// Parses "YYYY-MM-DD"
    init?(iso: String) {
        let parts = iso.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The date from its year, month and day
    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Earlier dates come first
    static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// A date and a time of day on the phone's clock, like Java's LocalDateTime
struct LocalDateTime: Hashable {
    /// The day
    let date: LocalDate
    /// The hour, 0 to 23
    let hour: Int
    /// The minute, 0 to 59
    let minute: Int
    /// The second, 0 to 59
    let second: Int

    /// A date and a time of day
    init(date: LocalDate, hour: Int, minute: Int, second: Int = 0) {
        self.date = date
        self.hour = hour
        self.minute = minute
        self.second = second
    }

    /// The moment in the phone's time zone
    init(_ moment: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: moment)
        self.init(date: LocalDate(year: c.year!, month: c.month!, day: c.day!), hour: c.hour!, minute: c.minute!, second: c.second!)
    }

    /// Now, on the phone's clock
    static var now: LocalDateTime { LocalDateTime(Date()) }

    /// Seconds since midnight
    var secondOfDay: Int { hour * 3600 + minute * 60 + second }
}
