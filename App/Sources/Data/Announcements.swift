import Foundation

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

    /// Keeps the last good feed in the app's caches folder
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
