import Foundation

/// One post from astikoktelkastorias.gr, as served by the astiko-ktel-announcements feed
struct Announcement: Codable, Hashable, Identifiable {
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
    let fetchedAt: String
    let announcements: [Announcement]
}

/// Downloads the announcements feed and keeps the last good copy on disk, so the list still shows offline
/// and the first frame doesn't wait for the network.
@MainActor
final class AnnouncementsStore: ObservableObject {
    /// nil until the cache or the network has answered
    @Published private(set) var announcements: [Announcement]?
    /// The last refresh couldn't reach the feed
    @Published private(set) var failed = false

    private let cacheFile: URL
    private var lastFetch = Date.distantPast
    private var refreshing = false

    /// Opening the screen again within this doesn't fetch the feed again
    private let minInterval: TimeInterval = 15 * 60

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        cacheFile = caches.appendingPathComponent("announcements.json")
    }

    /// Fetches the feed unless it was fetched in the last 15 minutes, or `force`
    func refresh(force: Bool = false) async {
        if announcements == nil { readCache() }
        if refreshing || (!force && Date().timeIntervalSince(lastFetch) < minInterval) { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let (body, response) = try await URLSession.shared.data(for: Endpoints.request(Endpoints.announcements, timeout: 10))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let feed = try JSONDecoder().decode(AnnouncementFeed.self, from: body)
            announcements = feed.announcements
            try? body.write(to: cacheFile, options: .atomic)
            lastFetch = Date()
            failed = false
        } catch {
            failed = true
        }
        // Show an empty list rather than loading forever when there's no cache either
        if announcements == nil { announcements = [] }
    }

    private func readCache() {
        guard let bytes = try? Data(contentsOf: cacheFile) else { return }
        if let feed = try? JSONDecoder().decode(AnnouncementFeed.self, from: bytes) {
            announcements = feed.announcements
        } else {
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }
}
