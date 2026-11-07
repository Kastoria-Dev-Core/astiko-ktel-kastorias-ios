import Foundation

/// A trip of the timetable that's sending where its bus is, and how far off the timetable it runs
struct LiveTrip: Hashable {
    /// `Line.id`
    let lineId: String
    /// `Direction.id`
    let directionId: String
    /// When the trip left its first stop by the timetable, minutes since midnight: which trip it is
    let tripStart: Int
    /// Minutes behind the timetable, or ahead when negative
    let delay: Int
    /// The last stop the bus has passed, as an index in the direction's stops
    let passedIndex: Int
}

/// Reads the server's ISO instants, with or without milliseconds
enum ISOTime {
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// The date in an ISO instant like "2026-10-31T08:15:27.000Z", or nil
    static func parse(_ text: String) -> Date? {
        fractional.date(from: text) ?? plain.date(from: text)
    }
}

/// Which trip each live bus is, and how late. The bus is placed on its direction between the two stops
/// it's nearest to, which by the timetable it reaches some minutes after leaving the first stop; of the
/// day's trips, the one that should be there closest to when the position was taken is the bus.
/// The same as the Android app's LiveTrips.kt.
enum LiveTrips {
    /// A bus further than this from its route is somewhere else: no times from it
    private static let maxOffRouteMeters = 300.0
    /// Delays outside this, in minutes, are more likely the wrong trip than a bus that far off
    private static let earliest = -5.0
    private static let latest = 30.0

    /// The live trips for the buses the server sent; `calendar` is the phone's, or a fixed one for the tests
    static func compute(data: TransitData, schedule: Schedule, buses: [LiveBus], calendar: Calendar = .current) -> [LiveTrip] {
        buses.compactMap { bus -> LiveTrip? in
            guard let line = data.line(bus.line), let direction = line.directions.first(where: { $0.id == bus.direction }) else { return nil }
            let stops: [(lat: Double, lng: Double, offset: Int)] = direction.stops.compactMap { ds in
                data.stop(ds.stop).map { (lat: $0.lat, lng: $0.lng, offset: ds.offset) }
            }
            if stops.count < 2 || stops.count != direction.stops.count { return nil }

            // Flat metres around the bus, close enough within a town
            let kx = 111_320.0 * cos(bus.lat * .pi / 180)
            let ky = 110_540.0
            func xy(_ lat: Double, _ lng: Double) -> (Double, Double) { ((lng - bus.lng) * kx, (lat - bus.lat) * ky) }

            var best: (segment: Int, fraction: Double, distance: Double)?
            for i in 0..<(stops.count - 1) {
                let (ax, ay) = xy(stops[i].lat, stops[i].lng)
                let (bx, by) = xy(stops[i + 1].lat, stops[i + 1].lng)
                let dx = bx - ax
                let dy = by - ay
                let length2 = dx * dx + dy * dy
                let t = length2 == 0 ? 0 : min(max((-ax * dx - ay * dy) / length2, 0), 1)
                let distance = hypot(ax + t * dx, ay + t * dy)
                if best == nil || distance < best!.distance { best = (segment: i, fraction: t, distance: distance) }
            }
            guard let found = best, found.distance <= maxOffRouteMeters else { return nil }
            if found.segment == 0 && found.fraction < 0.05 { return nil }

            let a = Double(stops[found.segment].offset)
            let b = Double(stops[found.segment + 1].offset)
            let scheduledOffset = a + found.fraction * (b - a)
            guard let seenAt = ISOTime.parse(bus.t) else { return nil }
            let seen = LocalDateTime(seenAt, calendar: calendar)
            let seenMinutes = Double(seen.hour * 60 + seen.minute) + Double(seen.second) / 60
            let trip = schedule.departures(line.id, direction.id, on: seen.date)
                .map { (start: $0, delay: seenMinutes - (Double($0) + scheduledOffset)) }
                .filter { $0.delay >= earliest && $0.delay <= latest }
                .min { abs($0.delay) < abs($1.delay) }
            guard let trip else { return nil }

            return LiveTrip(
                lineId: line.id,
                directionId: direction.id,
                tripStart: trip.start,
                delay: Int(trip.delay.rounded()),
                // Right at the next stop counts as passed too
                passedIndex: found.fraction > 0.95 ? found.segment + 1 : found.segment
            )
        }
    }
}

/// A bus to draw on the map, where it really is or where the timetable says it should be
struct BusOnMap: Hashable, Identifiable {
    let id: String
    /// The line it's running
    let line: Line
    /// Which way it's going
    let direction: Direction
    /// Latitude, WGS84
    let lat: Double
    /// Longitude, WGS84
    let lng: Double
    /// Sent by the phone in the bus, rather than estimated
    let live: Bool
}

/// The buses to draw: the ones sending where they are, and the timetable's estimates for the other lines.
/// A line with any bus sending shows only its real buses, so the same bus isn't drawn twice.
func busesOnMap(data: TransitData, estimated: [EstimatedBus], live: [LiveBus]) -> [BusOnMap] {
    let real: [BusOnMap] = live.compactMap { bus in
        guard let line = data.line(bus.line), let direction = line.directions.first(where: { $0.id == bus.direction }) else { return nil }
        return BusOnMap(id: "live-\(bus.vehicle)", line: line, direction: direction, lat: bus.lat, lng: bus.lng, live: true)
    }
    let liveLines = Set(real.map(\.line.id))
    let guessed = estimated.filter { !liveLines.contains($0.line.id) }.map {
        BusOnMap(id: "est-\($0.line.id)-\($0.direction.id)-\($0.departure)", line: $0.line, direction: $0.direction, lat: $0.lat, lng: $0.lng, live: false)
    }
    return real + guessed
}
