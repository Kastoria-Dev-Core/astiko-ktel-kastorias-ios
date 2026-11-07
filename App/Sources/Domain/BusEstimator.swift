import Foundation

/// A bus we think is on the road right now, from the timetable
struct EstimatedBus: Hashable {
    /// The line it's running
    let line: Line
    /// Which way it's going
    let direction: Direction
    /// Departure from the first stop, minutes since midnight
    let departure: Int
    /// Where it should be now, along the street path
    let lat: Double
    let lng: Double
    /// Direction of travel, degrees clockwise from north
    let bearing: Double
    /// The stop the bus reaches next
    let nextStopId: String
}

/// Works out where each bus should be from the timetable: a trip is on the road between leaving its
/// first stop and reaching its last, and between two stops it moves along the line's street path at the
/// pace the stop times give. The same as the Android app's BusEstimator.kt.
final class BusEstimator {
    private let data: TransitData
    private let schedule: Schedule

    /// One direction laid out along its street path, in metres on a flat plane around Kastoria
    private struct Track {
        let line: Line
        let direction: Direction
        /// The street path
        let points: [LatLng]
        /// The same points in metres (x east, y north)
        let xy: [(x: Double, y: Double)]
        /// Distance along the path to each point
        let cumulative: [Double]
        /// The direction's stop ids in order
        let stopIds: [String]
        /// Distance along the path to each stop
        let stopDistance: [Double]
        /// Seconds after the trip leaves its first stop that it reaches each stop
        let stopTime: [Double]
    }

    private lazy var tracks: [Track] = data.lines.flatMap { line in line.directions.compactMap { track(line, $0) } }

    /// How far along the path to look for the next stop
    private static let searchAheadMeters = 3_000.0

    init(data: TransitData, schedule: Schedule) {
        self.data = data
        self.schedule = schedule
    }

    /// The buses on the road at `now`
    func estimate(_ now: LocalDateTime) -> [EstimatedBus] {
        let nowSeconds = Double(now.secondOfDay)
        return tracks.flatMap { track -> [EstimatedBus] in
            guard let tripSeconds = track.stopTime.last else { return [] }
            return schedule.departures(track.line.id, track.direction.id, on: now.date).compactMap { departure in
                let elapsed = nowSeconds - Double(departure) * 60
                if elapsed < 0 || elapsed >= tripSeconds { return nil }
                return position(track, departure, elapsed)
            }
        }
    }

    private func position(_ track: Track, _ departure: Int, _ elapsed: Double) -> EstimatedBus? {
        let times = track.stopTime
        // The stretch between two stops the bus is on. Stretches of no time (same minute) are skipped.
        guard let i = (0..<(times.count - 1)).first(where: { elapsed >= times[$0] && elapsed < times[$0 + 1] }) else { return nil }
        let fraction = (elapsed - times[i]) / (times[i + 1] - times[i])
        let distance = track.stopDistance[i] + fraction * (track.stopDistance[i + 1] - track.stopDistance[i])
        let p = pointAt(track, distance)
        return EstimatedBus(line: track.line, direction: track.direction, departure: departure,
                            lat: p.lat, lng: p.lng, bearing: p.bearing, nextStopId: track.stopIds[i + 1])
    }

    /// The point `distance` metres along the track, and the bearing of the path there
    private func pointAt(_ track: Track, _ distance: Double) -> (lat: Double, lng: Double, bearing: Double) {
        let cumulative = track.cumulative
        var segment = min(max((cumulative.lastIndex { $0 <= distance } ?? 0), 0), cumulative.count - 2)
        // Step past zero-length segments so the bearing has a direction
        while segment < cumulative.count - 2 && cumulative[segment + 1] == cumulative[segment] { segment += 1 }
        let length = cumulative[segment + 1] - cumulative[segment]
        let t = length == 0 ? 0 : min(max((distance - cumulative[segment]) / length, 0), 1)
        let a = track.points[segment]
        let b = track.points[segment + 1]
        let axy = track.xy[segment]
        let bxy = track.xy[segment + 1]
        let bearing = (atan2(bxy.x - axy.x, bxy.y - axy.y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return (lat: a.lat + t * (b.lat - a.lat), lng: a.lng + t * (b.lng - a.lng), bearing: bearing)
    }

    private func track(_ line: Line, _ direction: Direction) -> Track? {
        let stops: [(stop: Stop, offset: Int)] = direction.stops.compactMap { s in data.stop(s.stop).map { (stop: $0, offset: s.offset) } }
        if stops.count < 2 { return nil }
        var points = data.directionPath(line, direction.id)
        if points.isEmpty { points = stops.map { LatLng(lat: $0.stop.lat, lng: $0.stop.lng) } }
        if points.count < 2 { return nil }

        let lat0 = points[0].lat
        let kx = 111_320.0 * cos(lat0 * .pi / 180)
        let ky = 110_540.0
        func toXY(_ lat: Double, _ lng: Double) -> (x: Double, y: Double) { (x: lng * kx, y: lat * ky) }
        let xy = points.map { toXY($0.lat, $0.lng) }
        var cumulative = [Double](repeating: 0, count: points.count)
        for k in 1..<xy.count {
            cumulative[k] = cumulative[k - 1] + hypot(xy[k].x - xy[k - 1].x, xy[k].y - xy[k - 1].y)
        }

        // Each stop's place along the path. Always searching forward from the previous stop,
        // so a path that passes the same street twice puts each stop on the right pass.
        var stopDistance = [Double](repeating: 0, count: stops.count)
        var segment = 0
        for (index, entry) in stops.enumerated() {
            let s = toXY(entry.stop.lat, entry.stop.lng)
            let reach = cumulative[segment] + BusEstimator.searchAheadMeters
            var best = Double.greatestFiniteMagnitude
            var bestSegment = segment
            var bestAlong = cumulative[segment]
            var j = segment
            while j < xy.count - 1 && cumulative[j] <= reach {
                let (d, along) = BusEstimator.project(s.x, s.y, xy[j], xy[j + 1])
                if d < best {
                    best = d
                    bestSegment = j
                    bestAlong = cumulative[j] + along
                }
                j += 1
            }
            segment = bestSegment
            stopDistance[index] = index == 0 ? bestAlong : max(bestAlong, stopDistance[index - 1])
        }

        return Track(line: line, direction: direction, points: points, xy: xy, cumulative: cumulative,
                     stopIds: stops.map(\.stop.id), stopDistance: stopDistance,
                     stopTime: BusEstimator.smoothTimes(stops.map(\.offset), stopDistance))
    }

    /// Distance from point (px, py) to segment ab, and how far along ab the closest point is, in metres
    private static func project(_ px: Double, _ py: Double, _ a: (x: Double, y: Double), _ b: (x: Double, y: Double)) -> (Double, Double) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length2 = dx * dx + dy * dy
        let t = length2 == 0 ? 0 : min(max(((px - a.x) * dx + (py - a.y) * dy) / length2, 0), 1)
        return (hypot(px - a.x - t * dx, py - a.y - t * dy), t * sqrt(length2))
    }

    /// Stop times in seconds. The timetable gives whole minutes, so several stops in a row can share a
    /// minute and the bus would jump between them. Those in-between stops get times spread by distance
    /// between the last stop before them and the next stop with a later minute.
    static func smoothTimes(_ offsetMinutes: [Int], _ stopDistance: [Double]) -> [Double] {
        var seconds = offsetMinutes.map { Double($0) * 60 }
        var i = 0
        while i < offsetMinutes.count {
            var next = i + 1
            while next < offsetMinutes.count && offsetMinutes[next] == offsetMinutes[i] { next += 1 }
            if next < offsetMinutes.count && next > i + 1 {
                let span = stopDistance[next] - stopDistance[i]
                for m in (i + 1)..<next {
                    let share = span > 0 ? (stopDistance[m] - stopDistance[i]) / span : Double(m - i) / Double(next - i)
                    seconds[m] = seconds[i] + share * (seconds[next] - seconds[i])
                }
            }
            i = next
        }
        return seconds
    }
}
