import CoreLocation
import Foundation
import UIKit

// The iOS 12 build's services: the same as App/Sources/Data, without SwiftUI, Combine or async/await (all iOS 13+).
// Changes reach the screens as notifications instead of @Published, and answers come back in callbacks, on the
// main thread.

extension Notification.Name {
    /// Favourites, theme, voice or language changed
    static let settingsChanged = Notification.Name("settingsChanged")
    /// New live trips arrived (every 15 seconds while the app is open)
    static let liveTripsChanged = Notification.Name("liveTripsChanged")
    /// The announcements list changed, or a refresh failed
    static let announcementsChanged = Notification.Name("announcementsChanged")
}

/// Light or dark theme, or whatever the phone is set to (always light on iOS 12, which has no dark mode)
enum ThemeMode: String {
    /// Follow the phone, always light, or always dark
    case system, light, dark
}

/// Favourite stops, theme, voice and language, kept in UserDefaults. The same keys as the SwiftUI app.
final class AppSettings {
    private let defaults: UserDefaults

    /// Favourite `Stop.id`s, in the order they were added
    private(set) var favorites: [String] {
        didSet {
            defaults.set(favorites.joined(separator: ","), forKey: "favorites")
            changed()
        }
    }

    /// The chosen theme, `.system` until one is picked
    var theme: ThemeMode {
        didSet {
            defaults.set(theme.rawValue, forKey: "theme")
            changed()
        }
    }

    /// Read out a stop's next departures when it opens
    var voice: Bool {
        didSet {
            defaults.set(voice, forKey: "voice")
            changed()
        }
    }

    /// "el" or "en"
    var language: String {
        didSet {
            defaults.set(language, forKey: "language")
            Strings.language = language
            changed()
        }
    }

    /// Reads the saved settings, the phone's language until one is picked
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favorites = (defaults.string(forKey: "favorites") ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
        theme = defaults.string(forKey: "theme").flatMap(ThemeMode.init(rawValue:)) ?? .system
        voice = defaults.bool(forKey: "voice")
        let saved = defaults.string(forKey: "language")
        let phone = Locale.preferredLanguages.first?.hasPrefix("el") == true ? "el" : "en"
        language = (saved == "el" || saved == "en") ? saved! : phone
        Strings.language = language
    }

    /// Adds the stop to the end of the favourites, or takes it out if it's there already
    func toggleFavorite(_ stopId: String) {
        if let index = favorites.firstIndex(of: stopId) {
            favorites.remove(at: index)
        } else {
            favorites.append(stopId)
        }
    }

    /// Whether the stop is one of the favourites
    func isFavorite(_ stopId: String) -> Bool { favorites.contains(stopId) }

    private func changed() {
        NotificationCenter.default.post(name: .settingsChanged, object: self)
    }
}

/// Loads the network: the downloaded copy when it's newer than the app's own transit.json. The same as the
/// SwiftUI app's TransitRepository, with a callback-free refresh that's used from the next start.
final class TransitRepository {
    private let cacheFile: URL
    private let etagFile: URL

    /// The whole network, read once
    let data: TransitData

    /// Reads the bundled transit.json, or the downloaded copy when it's newer
    init(bundle: Bundle = .main) {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        cacheFile = support.appendingPathComponent("transit.json")
        etagFile = support.appendingPathComponent("transit.json.etag")

        guard let url = bundle.url(forResource: "transit", withExtension: "json"),
              let bytes = try? Data(contentsOf: url),
              let bundled = try? JSONDecoder().decode(TransitBundle.self, from: bytes)
        else {
            fatalError("transit.json is missing from the app or unreadable")
        }
        if let cached = TransitRepository.readCache(cacheFile, etagFile), cached.meta.updated > bundled.meta.updated {
            data = TransitData(cached)
        } else {
            data = TransitData(bundled)
        }
    }

    /// Downloads the published bundle if it changed, for the next start. Fails quietly.
    func refresh() {
        var request = Endpoints.request(Endpoints.transitData, timeout: 20)
        if FileManager.default.fileExists(atPath: cacheFile.path), let etag = try? String(contentsOf: etagFile, encoding: .utf8) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let cacheFile = self.cacheFile
        let etagFile = self.etagFile
        URLSession.shared.dataTask(with: request) { body, response, _ in
            guard let body = body,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let bundle = try? JSONDecoder().decode(TransitBundle.self, from: body),
                  bundle.schema == TransitBundle.currentSchema, bundle.isUsable
            else { return }
            do {
                try body.write(to: cacheFile, options: .atomic)
                if let etag = http.allHeaderFields["ETag"] as? String {
                    try etag.write(to: etagFile, atomically: true, encoding: .utf8)
                } else {
                    try? FileManager.default.removeItem(at: etagFile)
                }
            } catch {
                // No room on the phone: try again next start
            }
        }.resume()
    }

    private static func readCache(_ cacheFile: URL, _ etagFile: URL) -> TransitBundle? {
        guard let bytes = try? Data(contentsOf: cacheFile) else { return nil }
        if let bundle = try? JSONDecoder().decode(TransitBundle.self, from: bytes),
           bundle.schema == TransitBundle.currentSchema, bundle.isUsable {
            return bundle
        }
        try? FileManager.default.removeItem(at: cacheFile)
        try? FileManager.default.removeItem(at: etagFile)
        return nil
    }
}

/// Downloads the announcements feed and keeps the last good copy on disk
final class AnnouncementsStore {
    /// nil until the cache or the network has answered
    private(set) var announcements: [Announcement]?
    /// The last refresh couldn't reach the feed
    private(set) var failed = false

    private let cacheFile: URL
    private var lastFetch = Date.distantPast
    private var refreshing = false
    private let minInterval: TimeInterval = 15 * 60

    /// Keeps the last good feed in the app's caches folder
    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        cacheFile = caches.appendingPathComponent("announcements.json")
    }

    /// Fetches the feed unless it was fetched in the last 15 minutes, or `force`
    func refresh(force: Bool = false) {
        if announcements == nil {
            readCache()
            if announcements != nil { changed() }
        }
        if refreshing || (!force && Date().timeIntervalSince(lastFetch) < minInterval) { return }
        refreshing = true
        URLSession.shared.dataTask(with: Endpoints.request(Endpoints.announcements, timeout: 10)) { body, response, _ in
            var feed: AnnouncementFeed?
            if let body = body, (response as? HTTPURLResponse)?.statusCode == 200 {
                feed = try? JSONDecoder().decode(AnnouncementFeed.self, from: body)
                if feed != nil { try? body.write(to: self.cacheFile, options: .atomic) }
            }
            DispatchQueue.main.async {
                self.refreshing = false
                if let feed = feed {
                    self.announcements = feed.announcements
                    self.lastFetch = Date()
                    self.failed = false
                } else {
                    self.failed = true
                }
                if self.announcements == nil { self.announcements = [] }
                self.changed()
            }
        }.resume()
    }

    private func readCache() {
        guard let bytes = try? Data(contentsOf: cacheFile) else { return }
        if let feed = try? JSONDecoder().decode(AnnouncementFeed.self, from: bytes) {
            announcements = feed.announcements
        } else {
            try? FileManager.default.removeItem(at: cacheFile)
        }
    }

    private func changed() {
        NotificationCenter.default.post(name: .announcementsChanged, object: self)
    }
}

/// Where the buses really are, from the drivers' phones. Asks at most every 10 seconds; with no answer for a
/// minute the buses are no longer shown as live.
final class LiveBusesRepository {
    private var last: [LiveBus] = []
    private var lastAskedAt = Date.distantPast
    private var lastGoodAt = Date.distantPast
    private let minInterval: TimeInterval = 10
    private let keep: TimeInterval = 60

    /// The buses on the road now, on the main thread; empty when none are sending or there's no network
    func buses(_ done: @escaping ([LiveBus]) -> Void) {
        let now = Date()
        guard now.timeIntervalSince(lastAskedAt) >= minInterval else {
            done(current())
            return
        }
        lastAskedAt = now
        URLSession.shared.dataTask(with: Endpoints.request(Endpoints.live, timeout: 8)) { body, response, _ in
            var feed: LiveFeed?
            if let body = body, (response as? HTTPURLResponse)?.statusCode == 200 {
                feed = try? JSONDecoder().decode(LiveFeed.self, from: body)
            }
            DispatchQueue.main.async {
                if let feed = feed {
                    self.last = feed.buses
                    self.lastGoodAt = Date()
                }
                done(self.current())
            }
        }.resume()
    }

    private func current() -> [LiveBus] {
        Date().timeIntervalSince(lastGoodAt) > keep ? [] : last
    }
}

/// Why there's no position
enum LocationError: Error {
    /// Location is off, the app isn't allowed, or no fix came
    case disabled, denied, noFix
}

/// One-shot current location, asking for the permission when it hasn't been asked yet
final class LocationClient: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var permissionWaiters: [() -> Void] = []
    private var fixWaiters: [(CLLocation?) -> Void] = []
    private let fixTimeout: TimeInterval = 10
    private let maxLastKnownAge: TimeInterval = 120

    /// Sets itself as the location manager's delegate, asking for the best accuracy
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private var status: CLAuthorizationStatus { CLLocationManager.authorizationStatus() }

    /// The app may read the location
    var hasPermission: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }

    /// The user said no, or the phone doesn't allow it
    var isDenied: Bool { status == .denied || status == .restricted }

    /// Asks for the permission if it hasn't been asked yet; true when it's granted
    func requestPermission(_ done: @escaping (Bool) -> Void) {
        if status == .notDetermined {
            permissionWaiters.append { [weak self] in done(self?.hasPermission ?? false) }
            manager.requestWhenInUseAuthorization()
        } else {
            done(hasPermission)
        }
    }

    /// Where the phone is. After 10 seconds without a fresh fix it settles for one from the last two minutes.
    func current(_ done: @escaping (Result<Coords, LocationError>) -> Void) {
        requestPermission { [weak self] granted in
            guard let self = self else { return }
            guard granted else { return done(.failure(.denied)) }
            guard CLLocationManager.locationServicesEnabled() else { return done(.failure(.disabled)) }
            self.fixWaiters.append { [weak self] fix in
                if let fix = fix {
                    return done(.success(Coords(lat: fix.coordinate.latitude, lng: fix.coordinate.longitude, accuracy: fix.horizontalAccuracy)))
                }
                if let self = self, let last = self.manager.location, -last.timestamp.timeIntervalSinceNow <= self.maxLastKnownAge {
                    return done(.success(Coords(lat: last.coordinate.latitude, lng: last.coordinate.longitude, accuracy: last.horizontalAccuracy)))
                }
                done(.failure(.noFix))
            }
            self.manager.requestLocation()
            DispatchQueue.main.asyncAfter(deadline: .now() + self.fixTimeout) { [weak self] in self?.finishFix(nil) }
        }
    }

    private func finishFix(_ location: CLLocation?) {
        let waiters = fixWaiters
        fixWaiters = []
        waiters.forEach { $0(location) }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard status != .notDetermined else { return }
        let waiters = permissionWaiters
        permissionWaiters = []
        waiters.forEach { $0() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finishFix(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finishFix(nil)
    }
}

/// Everything the screens share, made once
final class AppContainer {
    /// The one container of the app
    static let shared = AppContainer()

    /// Lines, stops and timetables
    let transit: TransitRepository
    /// The timetable logic
    let schedule: Schedule
    /// Where the buses should be by the timetable
    let busEstimator: BusEstimator
    /// Where the buses really are
    let liveBuses = LiveBusesRepository()
    /// The phone's position
    let location = LocationClient()
    /// The operator's announcements
    let announcements = AnnouncementsStore()
    /// Favourites, theme, voice and language
    let settings = AppSettings()

    /// The trips whose bus is sending where it is. Updated every 15 seconds while the app is open.
    private(set) var liveTrips: [LiveTrip] = []

    private var timer: Timer?

    /// The network
    var data: TransitData { transit.data }

    private init() {
        transit = TransitRepository()
        schedule = Schedule(transit.data)
        busEstimator = BusEstimator(data: transit.data, schedule: schedule)
    }

    /// Live trips now and every 15 seconds, until `stopLiveUpdates`
    func startLiveUpdates() {
        timer?.invalidate()
        refreshLiveTrips()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.refreshLiveTrips() }
    }

    /// No more live trips while the app is in the background
    func stopLiveUpdates() {
        timer?.invalidate()
        timer = nil
    }

    private func refreshLiveTrips() {
        liveBuses.buses { [weak self] buses in
            guard let self = self else { return }
            self.liveTrips = LiveTrips.compute(data: self.data, schedule: self.schedule, buses: buses)
            NotificationCenter.default.post(name: .liveTripsChanged, object: self)
        }
    }
}
