import Foundation

/// Light or dark theme, or whatever the phone is set to
enum ThemeMode: String, CaseIterable {
    case system, light, dark
}

/// Favourite stops (in the order they were added), theme, voice announcements and language, kept in
/// UserDefaults. A launch argument like `-language en` or `-theme dark` overrides the saved value, which
/// is how CI takes its screenshots.
@MainActor
final class AppSettings: ObservableObject {
    private let defaults: UserDefaults

    /// Favourite `Stop.id`s, in the order they were added
    @Published private(set) var favorites: [String] {
        didSet { defaults.set(favorites.joined(separator: ","), forKey: "favorites") }
    }

    /// The chosen theme, `.system` until one is picked
    @Published var theme: ThemeMode {
        didSet { defaults.set(theme.rawValue, forKey: "theme") }
    }

    /// Read out a stop's next departures when it opens. Off unless turned on in Settings.
    @Published var voice: Bool {
        didSet { defaults.set(voice, forKey: "voice") }
    }

    /// "el" or "en". The phone's language until one is picked in Settings.
    @Published var language: String {
        didSet {
            defaults.set(language, forKey: "language")
            Strings.language = language
        }
    }

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

    func isFavorite(_ stopId: String) -> Bool { favorites.contains(stopId) }
}
