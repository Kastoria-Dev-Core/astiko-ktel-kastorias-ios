import Foundation

/// A text in Greek and in English, e.g. a stop or line name
struct Localized: Codable, Hashable {
    /// Greek
    let el: String
    /// English, may be blank when there's no translation yet
    let en: String

    /// The text in `language` ("el" or "en"), falling back to Greek when the English is blank
    func get(_ language: String) -> String {
        if language == "el" { return el }
        return en.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? el : en
    }
}

/// A bus stop
struct Stop: Codable, Hashable, Identifiable {
    /// The operator's stop code, e.g. "16001"; shown as "Stop 16001"
    let id: String
    /// Its name, e.g. "Αφετηρία"; shown with `qualifier` where two share it
    let name: Localized
    /// Latitude, WGS84
    let lat: Double
    /// Longitude, WGS84
    let lng: Double
    /// Tells apart stops that share a name at the same place, e.g. the two "Αφετηρία" codes
    let qualifier: Localized?
}

/// A stop along a direction, with how long the bus takes to get there
struct DirectionStop: Codable, Hashable {
    /// `Stop.id`
    let stop: String
    /// Minutes after the trip leaves the first stop
    let offset: Int
}

/// An alternative ending: the stops from where it leaves the direction to its own last stop
struct Branch: Codable, Hashable {
    /// `Stop.id`s from the one where it turns off to its last
    let stops: [String]
    /// Street path as an encoded polyline, like `Direction.shape`
    let shape: String?
}

/// One way a line runs, e.g. out to the village or back to the Αφετηρία
struct Direction: Hashable, Identifiable {
    /// "out" or "in", unique within its line
    let id: String
    /// Where it's going, shown as "To …"
    let headsign: Localized
    /// Its stops in order, the first being where the timetable's times are from
    let stops: [DirectionStop]
    /// Street path through the stops as an encoded polyline; without it the map draws straight lines
    let shape: String?
    /// Other ways this direction can end
    let branches: [Branch]
}

extension Direction: Codable {
    private enum CodingKeys: String, CodingKey { case id, headsign, stops, shape, branches }

    /// Reads a direction; one without alternative endings leaves `branches` out
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        headsign = try c.decode(Localized.self, forKey: .headsign)
        stops = try c.decode([DirectionStop].self, forKey: .stops)
        shape = try c.decodeIfPresent(String.self, forKey: .shape)
        branches = try c.decodeIfPresent([Branch].self, forKey: .branches) ?? []
    }
}

/// A bus line with its directions
struct Line: Hashable, Identifiable {
    /// Two digits, e.g. "01"; what timetables and routes refer to
    let id: String
    /// As the operator writes it, e.g. "1"; badges pad it to two digits
    let number: String
    /// Where it serves, e.g. "Μεσοποταμία"
    let name: Localized
    /// Hex colour, e.g. "#C2410C"
    let color: String
    /// Hex colour of the number on the badge, readable on `color`
    let textColor: String
    /// Out and back: every line has two
    let directions: [Direction]
    /// A line that mainly serves the schools; drawn as an outlined badge
    let school: Bool

    /// The direction with this id, or the first one
    func direction(_ id: String?) -> Direction? {
        directions.first { $0.id == id } ?? directions.first
    }
}

extension Line: Codable {
    private enum CodingKeys: String, CodingKey { case id, number, name, color, textColor, directions, school }

    /// Reads a line; `school` is false when it's left out
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        number = try c.decode(String.self, forKey: .number)
        name = try c.decode(Localized.self, forKey: .name)
        color = try c.decode(String.self, forKey: .color)
        textColor = try c.decode(String.self, forKey: .textColor)
        directions = try c.decode([Direction].self, forKey: .directions)
        school = try c.decodeIfPresent(Bool.self, forKey: .school) ?? false
    }
}

/// Which timetable a day runs on. Holidays run on the Sunday one.
enum ServiceDay: String, Codable, CaseIterable, Hashable {
    /// Monday to Friday, Saturday, and Sunday and holidays
    case weekday, saturday, sunday
    /// Wednesdays only, for the few lines whose Wednesday differs from the other weekdays
    case wednesday
}

/// Winter or summer timetable; the summer period is `Meta.summer`
enum Season: String, Codable, Hashable {
    /// The two seasons of the timetables
    case winter, summer
}

/// The departures of one direction of a line on one kind of day
struct Timetable: Hashable {
    /// `Line.id`
    let line: String
    /// `Direction.id`
    let direction: String
    /// The kind of day it's for
    let service: ServiceDay
    /// The season it's for
    let season: Season
    /// Departure times from the first stop, "HH:MM"
    let departures: [String]
    /// What the operator's page says next to some departures, by their "HH:MM", in Greek
    let notes: [String: String]
}

extension Timetable: Codable {
    private enum CodingKeys: String, CodingKey { case line, direction, service, season, departures, notes }

    /// Reads a timetable; one without notes leaves `notes` out
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = try c.decode(String.self, forKey: .line)
        direction = try c.decode(String.self, forKey: .direction)
        service = try c.decode(ServiceDay.self, forKey: .service)
        season = try c.decode(Season.self, forKey: .season)
        departures = try c.decode([String].self, forKey: .departures)
        notes = try c.decodeIfPresent([String: String].self, forKey: .notes) ?? [:]
    }
}

/// A period of every year, e.g. the summer timetable from 20 June to 10 September
struct SeasonRange: Codable, Hashable {
    /// "MM-DD", inclusive
    let from: String
    /// "MM-DD", inclusive
    let to: String
}

/// About the data itself
struct Meta: Codable, Hashable {
    /// The timetables are made up, not the operator's; a banner says so
    let placeholder: Bool
    /// Where the timetables come from
    let source: String
    /// When the data was last updated, "YYYY-MM-DD"
    let updated: String
    /// Summer timetable period
    let summer: SeasonRange
    /// Fixed public holidays "MM-DD", served with the Sunday timetable
    let holidays: [String]
}

/// The whole network in one file, as the Android app's docs workflow publishes it (scripts/bundle_transit.py)
struct TransitBundle: Codable {
    /// Format version: a bundle with another one is ignored
    let schema: Int
    /// Every stop, from stops.json
    let stops: [Stop]
    /// Every line, from lines.json
    let lines: [Line]
    /// Every timetable, from timetables.json
    let timetables: [Timetable]
    /// `Meta.updated` decides whether a downloaded copy is newer than the app's own
    let meta: Meta

    /// The bundle format this app reads
    static let currentSchema = 1

    /// Complete enough to run the app on: nothing empty and nothing pointing at a stop or line that isn't there
    var isUsable: Bool {
        if stops.isEmpty || lines.isEmpty || timetables.isEmpty { return false }
        let stopIds = Set(stops.map(\.id))
        let lineIds = Set(lines.map(\.id))
        return lines.allSatisfy { line in line.directions.allSatisfy { d in d.stops.allSatisfy { stopIds.contains($0.stop) } } }
            && timetables.allSatisfy { lineIds.contains($0.line) }
    }
}

/// A point on the map
struct LatLng: Hashable {
    /// Latitude, WGS84
    let lat: Double
    /// Longitude, WGS84
    let lng: Double
}

/// Everything the app knows about the network
final class TransitData {
    /// Every stop
    let stops: [Stop]
    /// Every line, in their order
    let lines: [Line]
    /// Every timetable
    let timetables: [Timetable]
    /// About the data: season, holidays, when it was updated
    let meta: Meta

    private let stopById: [String: Stop]
    private let lineById: [String: Line]

    /// Keeps the network and indexes the stops and lines by id
    init(stops: [Stop], lines: [Line], timetables: [Timetable], meta: Meta) {
        self.stops = stops
        self.lines = lines
        self.timetables = timetables
        self.meta = meta
        stopById = Dictionary(stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lineById = Dictionary(lines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The network from a downloaded or bundled transit.json
    convenience init(_ bundle: TransitBundle) {
        self.init(stops: bundle.stops, lines: bundle.lines, timetables: bundle.timetables, meta: bundle.meta)
    }

    /// The stop with this id, or nil
    func stop(_ id: String?) -> Stop? {
        guard let id else { return nil }
        return stopById[id]
    }

    /// The line with this id, or nil
    func line(_ id: String?) -> Line? {
        guard let id else { return nil }
        return lineById[id]
    }

    /// Lines that stop at a stop, in line order, including the stops of alternative endings
    func linesAtStop(_ stopId: String) -> [Line] {
        lines.filter { line in
            line.directions.contains { d in
                d.stops.contains { $0.stop == stopId } || d.branches.contains { $0.stops.contains(stopId) }
            }
        }
    }

    /// Every stop a line can call at, in either direction or on an alternative ending
    func lineStopIds(_ line: Line) -> Set<String> {
        Set(line.directions.flatMap { d in d.stops.map(\.stop) + d.branches.flatMap(\.stops) })
    }

    /// Stops of a direction in order
    func directionStops(_ line: Line, _ directionId: String) -> [Stop] {
        guard let direction = line.direction(directionId) else { return [] }
        return direction.stops.compactMap { stop($0.stop) }
    }

    /// The path a direction takes on the map: along the streets when known, else stop to stop
    func directionPath(_ line: Line, _ directionId: String) -> [LatLng] {
        guard let direction = line.direction(directionId) else { return [] }
        if let shape = direction.shape { return Geo.decodePolyline(shape) }
        return directionStops(line, directionId).map { LatLng(lat: $0.lat, lng: $0.lng) }
    }

    /// Paths of a direction's alternative endings
    func branchPaths(_ line: Line, _ directionId: String) -> [[LatLng]] {
        guard let direction = line.directions.first(where: { $0.id == directionId }) else { return [] }
        return direction.branches.map { branch in
            if let shape = branch.shape { return Geo.decodePolyline(shape) }
            return branch.stops.compactMap { stop($0) }.map { LatLng(lat: $0.lat, lng: $0.lng) }
        }
    }
}

/// One bus leaving a stop
struct Departure: Hashable, Identifiable {
    /// The line of the bus
    let line: Line
    /// Which way it's going
    let direction: Direction
    /// Minutes since midnight of the service date
    var minutes: Int
    /// Days from today: 0 today, 1 tomorrow
    let dayOffset: Int
    /// Last trip of this line and direction on that service day
    let last: Bool
    /// The operator's note about this trip; nil for most
    let note: String?
    /// When the trip leaves its first stop, minutes since midnight: which trip of the day it is
    let tripStart: Int
    /// Where the stop is in `Direction.stops`, to tell whether a live bus has passed it
    let stopIndex: Int
    /// `minutes` comes from where the bus really is, not from the timetable alone
    var live: Bool = false

    var id: String { "\(line.id)-\(direction.id)-\(tripStart)-\(dayOffset)-\(stopIndex)" }
}
