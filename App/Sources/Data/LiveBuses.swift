import Foundation

/// A bus that sent where it is, from the phone kept in it (astiko-ktel-odigoi)
struct LiveBus: Codable, Hashable {
    /// The bus, e.g. "12"
    let vehicle: String
    /// `Line.id`
    let line: String
    /// `Direction.id`
    let direction: String
    let lat: Double
    let lng: Double
    /// Direction of travel, degrees clockwise from north, when the phone knew it
    let bearing: Double?
    /// Metres per second, when the phone knew it
    let speed: Double?
    /// When the phone got the position, ISO instant
    let t: String
}

/// What the server answers
struct LiveFeed: Codable {
    /// When the server made the answer
    let updated: String
    /// The buses heard from in the last two minutes
    let buses: [LiveBus]
}

/// Where the buses really are, from the drivers' phones through the astiko-ktel-live server. Asks at most
/// every 10 seconds; with no signal the last answer is kept for a minute, then nothing, so the map goes back
/// to the timetable's estimates instead of showing buses where they were.
actor LiveBusesRepository {
    private var last: [LiveBus] = []
    private var lastAskedAt = Date.distantPast
    private var lastGoodAt = Date.distantPast

    /// The server's answer is cached for 10 seconds anyway
    private let minInterval: TimeInterval = 10
    /// With no answer for this long, the buses are no longer shown as live
    private let keep: TimeInterval = 60

    /// The buses on the road now; empty when none are sending or the server can't be reached
    func buses() async -> [LiveBus] {
        let now = Date()
        if now.timeIntervalSince(lastAskedAt) >= minInterval {
            lastAskedAt = now
            if let answer = try? await URLSession.shared.data(for: Endpoints.request(Endpoints.live, timeout: 8)),
               (answer.1 as? HTTPURLResponse)?.statusCode == 200,
               let feed = try? JSONDecoder().decode(LiveFeed.self, from: answer.0) {
                last = feed.buses
                lastGoodAt = Date()
            }
        }
        return Date().timeIntervalSince(lastGoodAt) > keep ? [] : last
    }
}
