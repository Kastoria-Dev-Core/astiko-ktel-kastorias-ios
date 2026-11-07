import SwiftUI

/// Where finding the user's position is at, for "Where do you want to go?"
enum NearbyState: Equatable {
    /// Not asked yet, waiting for a fix, refused, location off, or no fix
    case idle, loading, denied, disabled, error
    /// Found
    case ready(Coords)

    /// Where the user is, once found
    var coords: Coords? {
        if case .ready(let coords) = self { return coords }
        return nil
    }
}

/// The first screen: search, "Where do you want to go?", favourite stops with their next buses, and the
/// latest announcement
struct HomeScreen: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var announcements: AnnouncementsStore
    @State private var query = ""
    @State private var editingFavorites = false
    @State private var favoriteQuery = ""
    @State private var destination: Destination?
    @State private var nearby: NearbyState = .idle

    var body: some View {
        Ticking { now in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    header(now)
                    PlaceholderBanner(visible: container.data.meta.placeholder)
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        SearchResults(query: query)
                    } else {
                        JourneySection(destination: $destination, nearby: nearby, now: now, onLocate: locate)
                        favorites(now)
                        announcementSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(AC.background)
        .toolbar(.hidden, for: .navigationBar)
        .task { await announcements.refresh() }
    }

    // MARK: - Header

    private func header(_ now: LocalDateTime) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image("AppMark")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(AC.primary)
                    .frame(width: 36, height: 35)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("app_title")).font(.brand(19, .semibold)).foregroundStyle(AC.onBackground)
                    Text(dateLine(now)).font(.brand(13)).foregroundStyle(AC.muted)
                }
                Spacer()
                NavigationLink(value: Route.settings) {
                    Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(AC.ink2).frame(width: 44, height: 44)
                }
                .accessibilityLabel(L("tab_settings"))
            }
            SearchField(text: $query, placeholder: L("search_stops"))
        }
        .padding(.top, 12)
    }

    /// "Σάββατο 7 Νοεμβρίου · Σάββατο": the date and what kind of day it runs as
    private func dateLine(_ now: LocalDateTime) -> String {
        let formatter = DateFormatter()
        formatter.locale = appLocale
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        let date = formatter.string(from: Date())
        let schedule = container.schedule
        let day: String
        if schedule.isHoliday(now.date) {
            day = L("day_holiday")
        } else {
            switch schedule.serviceDay(for: now.date) {
            case .weekday, .wednesday: day = L("day_weekday")
            case .saturday: day = L("day_saturday")
            case .sunday: day = L("day_sunday")
            }
        }
        return String(date.prefix(1)).uppercased() + String(date.dropFirst()) + " · " + day
    }

    // MARK: - Favourites

    @ViewBuilder
    private func favorites(_ now: LocalDateTime) -> some View {
        let stops = settings.favorites.compactMap { container.data.stop($0) }
        SectionTitle(text: L("favorites")) {
            if !stops.isEmpty || editingFavorites {
                Button(L(editingFavorites ? "done" : "edit")) { editingFavorites.toggle() }
                    .font(.brand(15, .semibold))
                    .foregroundStyle(AC.link)
            }
        }
        if editingFavorites {
            FavoritePicker(query: $favoriteQuery)
        } else if stops.isEmpty {
            AppCard {
                Text(L("favorites_empty")).font(.brand(14)).foregroundStyle(AC.muted)
                Button(L("find_stop")) { editingFavorites = true }
                    .font(.brand(15, .semibold))
                    .foregroundStyle(AC.link)
            }
        }
        ForEach(stops) { stop in
            StopCard(stop: stop,
                     departures: container.schedule.nextDepartures(stop.id, now: now, limit: 3, live: container.liveTrips),
                     now: now)
        }
    }

    // MARK: - Announcements

    @ViewBuilder
    private var announcementSection: some View {
        SectionTitle(text: L("announcements")) {
            NavigationLink(L("announcements_all"), value: Route.announcements)
                .font(.brand(15))
                .foregroundStyle(AC.link)
        }
        if let latest = announcements.announcements?.first {
            NavigationLink(value: Route.announcements) {
                AnnouncementRow(announcement: latest)
            }
            .buttonStyle(.plain)
        } else {
            Text(L("announcements_none")).font(.brand(14)).foregroundStyle(AC.muted)
        }
    }

    // MARK: - Location

    private func locate() {
        nearby = .loading
        Task {
            do {
                nearby = .ready(try await container.location.current())
            } catch LocationError.denied {
                nearby = .denied
            } catch LocationError.disabled {
                nearby = .disabled
            } catch {
                nearby = .error
            }
        }
    }
}

/// The search box: a magnifier, the text, and a button to clear it
struct SearchField: View {
    /// What's typed
    @Binding var text: String
    /// Shown while it's empty
    let placeholder: String
    /// The smaller field inside the favourites picker
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(AC.muted)
            TextField(placeholder, text: $text)
                .font(.brand(compact ? 14 : 16))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AC.muted)
                }
                .accessibilityLabel(L("clear_search"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: compact ? 44 : 52)
        .background(compact ? AC.surfaceVariant.opacity(0.5) : AC.surface, in: RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
        .overlay {
            if !compact { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AC.border, lineWidth: 1) }
        }
    }
}

/// What the search box found: lines first, then stops
private struct SearchResults: View {
    let query: String
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        let data = container.data
        let lines = Search.lines(data.lines, query)
        let stops = Search.stops(data.stops, query, language: Strings.language)
        AppCard(spacing: 4) {
            if lines.isEmpty && stops.isEmpty {
                Text(L("no_results")).font(.brand(14)).foregroundStyle(AC.muted)
            }
            if !lines.isEmpty {
                Text(L("tab_lines")).font(.brand(12, .semibold)).foregroundStyle(AC.muted)
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Divider().overlay(AC.border) }
                    NavigationLink(value: Route.line(line.id, nil)) {
                        HStack(spacing: 12) {
                            LineBadge(line: line)
                            Text(line.name.text).font(.brand(15, .medium)).lineLimit(1)
                            Spacer()
                        }
                        .frame(minHeight: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !stops.isEmpty { Divider().overlay(AC.border).padding(.vertical, 6) }
            }
            if !stops.isEmpty {
                if !lines.isEmpty { Text(L("find_stop")).font(.brand(12, .semibold)).foregroundStyle(AC.muted) }
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    if index > 0 { Divider().overlay(AC.border) }
                    let here = data.linesAtStop(stop.id)
                    NavigationLink(value: Route.stop(stop.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: "mappin.and.ellipse").foregroundStyle(AC.muted)
                            Text(stop.title).font(.brand(15, .medium)).lineLimit(2).multilineTextAlignment(.leading)
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(here.prefix(3)) { LineBadge(line: $0) }
                                if here.count > 3 { Text("+\(here.count - 3)").font(.brand(12, .medium)).foregroundStyle(AC.muted) }
                            }
                        }
                        .frame(minHeight: 52)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Picking favourite stops: a search and every stop with its star
private struct FavoritePicker: View {
    @Binding var query: String
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let all = container.data.stops
        let shown = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? all.sorted { $0.name.text < $1.name.text }
            : Search.stops(all, query, language: Strings.language)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: settings.favorites.isEmpty ? "star" : "star.fill")
                    .foregroundStyle(settings.favorites.isEmpty ? AC.link : AC.star)
                Text(settings.favorites.isEmpty ? L("select_favorite_stops") : "\(L("select_favorite_stops")) (\(settings.favorites.count))")
                    .font(.brand(14, .semibold))
            }
            SearchField(text: $query, placeholder: L("search_stops"), compact: true)
            if shown.isEmpty {
                Text(L("no_results")).font(.brand(13)).foregroundStyle(AC.muted).padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(shown) { stop in
                            let on = settings.isFavorite(stop.id)
                            Button {
                                settings.toggleFavorite(stop.id)
                            } label: {
                                HStack {
                                    Text(stop.title).font(.brand(14, on ? .semibold : .regular)).multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: on ? "star.fill" : "star").foregroundStyle(on ? AC.star : AC.muted)
                                }
                                .padding(.horizontal, 8)
                                .frame(minHeight: 40)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(12)
        .background(AC.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(AC.border, lineWidth: 1))
    }
}
