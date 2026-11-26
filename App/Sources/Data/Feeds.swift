import Foundation

// What the app downloads, shared by the app and the iOS 12 build (Legacy/): plain types, no SwiftUI,
// no Combine and no async, so both can compile them.

/// The addresses the app talks to, the same as the Android app's
enum Endpoints {
    /// The whole network, published by the Android repo's docs workflow, so a timetable change reaches
    /// users without a new release
    static let transitData = URL(string: "https://kastoria-dev-core.github.io/astiko-ktel-kastorias-app/data/transit.json")!
    /// The operator's announcements, from the astiko-ktel-announcements cron job
    static let announcements = URL(string: "https://astiko-ktel-announcements.vercel.app/api/announcements?kind=service")!
    /// Where the buses really are, sent by the drivers' phones (astiko-ktel-odigoi)
    static let live = URL(string: "https://astiko-ktel-live.vercel.app/api/positions")!

    /// Sent as the User-Agent: the app's id and version
    static var userAgent: String {
        let info = Bundle.main.infoDictionary
        let id = Bundle.main.bundleIdentifier ?? "com.kastoriadevs.astikoktel"
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        return "\(id)/\(version) (iOS)"
    }

    /// A GET with the app's User-Agent and a JSON Accept header
    static func request(_ url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}

/// A bus that sent where it is, from the phone kept in it (astiko-ktel-odigoi)
struct LiveBus: Codable, Hashable {
    /// The bus, e.g. "12"
    let vehicle: String
    /// `Line.id`
    let line: String
    /// `Direction.id`
    let direction: String
    /// Latitude, WGS84
    let lat: Double
    /// Longitude, WGS84
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

/// One post from astikoktelkastorias.gr, as served by the astiko-ktel-announcements feed
struct Announcement: Codable, Hashable {
    /// Unique per post
    let id: Int64
    /// As the operator wrote it
    let title: String
    /// Often empty: most announcements are a poster image with no text
    let text: String
    /// "service" or "corporate"
    let kind: String
    /// ISO instant
    let published: String
    /// The post on astikoktelkastorias.gr
    let url: String
    /// The poster, when there is one
    let image: String?
    /// "YYYY-MM-DD" dates mentioned in the title/text
    let dates: [String]
    /// Last of `dates`, nil when the announcement mentions none
    let validUntil: String?

    private enum CodingKeys: String, CodingKey { case id, title, text, kind, published, url, image, dates, validUntil }

    /// Reads an announcement, with defaults for the fields the feed may leave out
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int64.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "service"
        published = try c.decode(String.self, forKey: .published)
        url = try c.decode(String.self, forKey: .url)
        image = try c.decodeIfPresent(String.self, forKey: .image)
        dates = try c.decodeIfPresent([String].self, forKey: .dates) ?? []
        validUntil = try c.decodeIfPresent(String.self, forKey: .validUntil)
    }

    /// `published` parsed
    var publishedAt: Date { ISOTime.parse(published) ?? .distantPast }

    /// How long an announcement that mentions no date stays current
    static let undatedDays = 7

    /// Still relevant: its last mentioned date hasn't passed, or, when it mentions no date, it was
    /// published within the last week
    func isActive(today: LocalDate, now: Date) -> Bool {
        if let until = validUntil.flatMap(LocalDate.init(iso:)) { return !(until < today) }
        return publishedAt > now.addingTimeInterval(-Double(Announcement.undatedDays) * 86_400)
    }
}

/// The feed as a whole, also what's kept in the cache file
struct AnnouncementFeed: Codable {
    /// When the feed was made, ISO instant
    let fetchedAt: String
    /// Every announcement the feed has, newest first
    let announcements: [Announcement]
}
