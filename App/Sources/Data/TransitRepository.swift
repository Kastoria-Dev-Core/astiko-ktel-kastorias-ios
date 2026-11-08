import Foundation

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

/// Loads the network: the copy downloaded from `Endpoints.transitData` when it's newer than the one built
/// into the app, otherwise the app's own transit.json.
///
/// `refresh()` downloads a new copy when the published one has changed. It's used from the next start of
/// the app, so the screens never see the data change under them.
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
        // A downloaded copy older than the app's own (e.g. after an app update) is left unused
        if let cached = TransitRepository.readCache(cacheFile, etagFile), cached.meta.updated > bundled.meta.updated {
            data = TransitData(cached)
        } else {
            data = TransitData(bundled)
        }
    }

    /// Downloads the published bundle if it changed since the last download, and keeps it for the next
    /// start. Fails quietly: without a network or with a bad file, the current data stays.
    func refresh() async {
        var request = Endpoints.request(Endpoints.transitData, timeout: 20)
        if FileManager.default.fileExists(atPath: cacheFile.path), let etag = try? String(contentsOf: etagFile, encoding: .utf8) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        guard let answer = try? await URLSession.shared.data(for: request),
              let http = answer.1 as? HTTPURLResponse, http.statusCode == 200,
              let bundle = try? JSONDecoder().decode(TransitBundle.self, from: answer.0),
              bundle.schema == TransitBundle.currentSchema, bundle.isUsable
        else { return }
        // Written aside and moved into place, so a crash halfway never leaves half a file
        do {
            try answer.0.write(to: cacheFile, options: .atomic)
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                try etag.write(to: etagFile, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: etagFile)
            }
        } catch {
            // No room on the phone: try again next start
        }
    }

    private static func readCache(_ cacheFile: URL, _ etagFile: URL) -> TransitBundle? {
        guard let bytes = try? Data(contentsOf: cacheFile) else { return nil }
        if let bundle = try? JSONDecoder().decode(TransitBundle.self, from: bytes),
           bundle.schema == TransitBundle.currentSchema, bundle.isUsable {
            return bundle
        }
        // Unreadable or from an older format: drop it, the next refresh downloads a good one
        try? FileManager.default.removeItem(at: cacheFile)
        try? FileManager.default.removeItem(at: etagFile)
        return nil
    }
}
