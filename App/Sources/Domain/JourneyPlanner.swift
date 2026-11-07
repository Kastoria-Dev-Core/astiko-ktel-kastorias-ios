import Foundation

/// The places offered in "Where do you want to go?", each with the stops that count as "there"
enum Destination: String, CaseIterable, Identifiable {
    /// Αφετηρία and Αφετηρία 2, the terminal in the centre: almost every line starts and ends there
    case centre
    /// Every stop of Μανιάκοι
    case maniakoi
    /// Πανεπιστήμιο and Πανεπιστήμιο 2, one on each side of the road
    case university

    var id: String { rawValue }

    /// Getting off at any of them counts as arriving
    var stopIds: Set<String> {
        switch self {
        case .centre: return ["16001", "16053", "16600"]
        case .maniakoi: return ["16193", "16127", "16131", "16194", "16195", "16128", "16130", "16129", "16132"]
        case .university: return ["16114", "16119"]
        }
    }
}

/// A stop and how far it is from the user
struct NearbyStop: Hashable {
    /// The stop
    let stop: Stop
    /// Straight-line distance from the user
    let distanceMeters: Double

    /// Minutes to walk there, rounded up. Straight-line distance, so we walk a bit slowly (about 4 km/h).
    var walkMinutes: Int { Int(ceil(distanceMeters / 70.0)) }
}

/// A direction that takes you from `board` (near you) to `alightStopId` (at the destination)
struct Ride: Hashable {
    /// The line to take
    let line: Line
    /// The way the line has to be going to reach the destination
    let direction: Direction
    /// Where to get on
    let board: NearbyStop
    /// Minutes after the trip leaves its first stop that it reaches `board`
    let boardOffset: Int
    /// The first destination stop after `board`, where to get off
    let alightStopId: String
}

/// The next bus of a ride you can still walk to in time, and the one after it
struct JourneyOption: Hashable, Identifiable {
    /// Which line, from where, to where
    let ride: Ride
    /// When the bus reaches the boarding stop, minutes since midnight
    let minutes: Int
    /// Minutes from now until then
    let minutesUntil: Int
    /// The bus after it at the same stop, or nil when it's the last today
    let later: Int?

    var id: String { "\(ride.line.id)-\(ride.direction.id)-\(ride.board.stop.id)" }
}

/// How a plan turned out, which decides what "Where do you want to go?" shows
enum JourneyStatus {
    /// The closest stop is more than `maxSearchMeters` away: not in Kastoria
    case tooFar
    /// A stop of the destination is within `alreadyThereMeters`
    case alreadyThere
    /// No line goes from a stop nearby to the destination
    case noRoute
    /// Lines go there, but none has a bus left today that can still be caught
    case noMoreBuses
    /// There are buses to take
    case ready
}

/// The answer to "Where do you want to go?" for one destination
struct JourneyPlan {
    /// What came of it; `options` is empty unless `.ready`
    let status: JourneyStatus
    /// The stop closest to the user, whether or not a bus from it goes there
    let nearestStop: NearbyStop
    /// The closest stop with a bus to the destination, when it's not `nearestStop`
    let usefulStop: NearbyStop?
    /// Soonest first
    let options: [JourneyOption]
}

/// Finds the buses that go from near the user to a destination, using only the direction stop lists and
/// today's timetables. The same as the Android app's JourneyPlanner.kt.
enum JourneyPlanner {
    /// Stops up to this far are an easy walk: we look here first
    static let maxWalkMeters = 1_000.0
    /// If no stop within `maxWalkMeters` goes there, we look this far for one that does
    static let maxSearchMeters = 3_000.0
    /// Closer than this to a destination stop: you are already there
    static let alreadyThereMeters = 300.0
    /// Rides from stops this much further than the closest useful stop are shown too
    private static let extraWalkMeters = 300.0

    /// The plan for getting from a point to `destination` at `now`, or nil when there are no stops. Stops close by come first; further ones are only looked at when none of those has a bus that goes there.
    static func plan(data: TransitData, schedule: Schedule, destination: Destination, lat: Double, lng: Double, now: LocalDateTime) -> JourneyPlan? {
        let nearby = data.stops
            .map { NearbyStop(stop: $0, distanceMeters: Geo.distanceMeters(lat, lng, $0.lat, $0.lng)) }
            .sorted { $0.distanceMeters < $1.distanceMeters }
        guard let nearest = nearby.first else { return nil }
        // Outside Kastoria no stop is a walk away, however close the "closest" one is
        if nearest.distanceMeters > maxSearchMeters {
            return JourneyPlan(status: .tooFar, nearestStop: nearest, usefulStop: nil, options: [])
        }
        if isAlreadyThere(nearby, destination) {
            return JourneyPlan(status: .alreadyThere, nearestStop: nearest, usefulStop: nil, options: [])
        }
        // A direction with no timetable never has a bus to show, so it can't take you there
        let timed = Set(data.timetables.filter { !$0.departures.isEmpty }.map { "\($0.line)|\($0.direction)" })
        let lines = data.lines.map { line in
            Line(id: line.id, number: line.number, name: line.name, color: line.color, textColor: line.textColor,
                 directions: line.directions.filter { timed.contains("\(line.id)|\($0.id)") }, school: line.school)
        }
        var rides = nearestRides(findRides(stopsWithin(nearby, maxWalkMeters), lines, destination))
        if rides.isEmpty { rides = nearestRides(findRides(stopsWithin(nearby, maxSearchMeters), lines, destination)) }
        if rides.isEmpty { return JourneyPlan(status: .noRoute, nearestStop: nearest, usefulStop: nil, options: []) }

        let found = options(rides, schedule, now)
        // The closest stop among the buses we show, or among all rides when no bus is left today
        let pool = found.isEmpty ? rides : found.map(\.ride)
        let closest = pool.min { $0.board.distanceMeters < $1.board.distanceMeters }?.board
        let useful = closest?.stop.id == nearest.stop.id ? nil : closest
        return JourneyPlan(status: found.isEmpty ? .noMoreBuses : .ready, nearestStop: nearest, usefulStop: useful, options: found)
    }

    /// The stops up to `meters` away, closest first. The closest stop is always included.
    static func stopsWithin(_ nearbySorted: [NearbyStop], _ meters: Double) -> [NearbyStop] {
        nearbySorted.enumerated().filter { $0.offset == 0 || $0.element.distanceMeters <= meters }.map(\.element)
    }

    /// Keeps the rides worth walking to
    static func nearestRides(_ rides: [Ride]) -> [Ride] {
        guard let closest = rides.map(\.board.distanceMeters).min() else { return [] }
        let limit = max(maxWalkMeters, closest + extraWalkMeters)
        return rides.filter { $0.board.distanceMeters <= limit }
    }

    /// A stop of `destination` is within `alreadyThereMeters`
    static func isAlreadyThere(_ nearbySorted: [NearbyStop], _ destination: Destination) -> Bool {
        nearbySorted.contains { destination.stopIds.contains($0.stop.id) && $0.distanceMeters <= alreadyThereMeters }
    }

    /// For each direction, the closest boarding stop from which it later reaches a destination stop
    static func findRides(_ boardingStops: [NearbyStop], _ lines: [Line], _ destination: Destination) -> [Ride] {
        var rides: [Ride] = []
        for line in lines {
            for direction in line.directions {
                let ids = direction.stops.map(\.stop)
                search: for board in boardingStops where !destination.stopIds.contains(board.stop.id) {
                    // A stop can appear twice in a direction (rare): try every pass
                    for boardIndex in ids.indices where ids[boardIndex] == board.stop.id {
                        if let alight = ((boardIndex + 1)..<ids.count).first(where: { destination.stopIds.contains(ids[$0]) }) {
                            rides.append(Ride(line: line, direction: direction, board: board,
                                              boardOffset: direction.stops[boardIndex].offset, alightStopId: ids[alight]))
                            break search
                        }
                    }
                }
            }
        }
        return rides
    }

    /// The next catchable bus of every ride today, soonest first
    static func options(_ rides: [Ride], _ schedule: Schedule, _ now: LocalDateTime) -> [JourneyOption] {
        let nowMin = Schedule.minutesOfDay(now)
        return rides.compactMap { ride -> JourneyOption? in
            let catchable = schedule.departures(ride.line.id, ride.direction.id, on: now.date)
                .map { $0 + ride.boardOffset }
                .filter { $0 - nowMin >= ride.board.walkMinutes }
            guard let first = catchable.first else { return nil }
            return JourneyOption(ride: ride, minutes: first, minutesUntil: first - nowMin, later: catchable.count > 1 ? catchable[1] : nil)
        }
        .sorted { ($0.minutesUntil, $0.ride.board.distanceMeters) < ($1.minutesUntil, $1.ride.board.distanceMeters) }
    }
}
