import UIKit

/// Where finding the user's position is at, for "Where do you want to go?"
enum NearbyState: Equatable {
    case idle, loading, denied, disabled, error
    case ready(Coords)

    var coords: Coords? {
        if case .ready(let coords) = self { return coords }
        return nil
    }
}

extension Destination {
    /// Its name on the chip, e.g. "Κέντρο"
    var label: String {
        switch self {
        case .centre: return L("destination_centre")
        case .maniakoi: return L("destination_maniakoi")
        case .university: return L("destination_university")
        }
    }
}

/// The first screen: search, "Where do you want to go?", favourite stops with their next buses, and the
/// latest announcement
final class HomeViewController: ScrollScreen {
    override var hidesNavigationBar: Bool { true }

    private let container = AppContainer.shared
    private let dateLabel = makeLabel("", 13, .regular, AC.muted)
    private lazy var search = SearchField(placeholder: L("search_stops")) { [weak self] _ in self?.reload() }
    private let results = vstack([], spacing: 12)
    private let journey = vstack([])
    private let favoritesHeader = vstack([])
    private lazy var picker = FavoritePickerView()
    private let favoritesList = vstack([], spacing: 12)
    private let announcementsBox = vstack([], spacing: 12)

    private var editingFavorites = false
    private var destination: Destination?
    private var nearby: NearbyState = .idle
    private var showAll = false

    override func viewDidLoad() {
        contentInsets = UIEdgeInsets(top: 12, left: 16, bottom: 20, right: 16)
        super.viewDidLoad()
        let mark = UIImageView(image: UIImage(named: "AppMark")?.withRenderingMode(.alwaysTemplate))
        mark.tintColor = AC.primary
        mark.contentMode = .scaleAspectFit
        sized(mark, width: 36, height: 35)
        let titles = squeeze(vstack([makeLabel(L("app_title"), 19, .semibold), dateLabel], spacing: 1))
        let gear = sized(ActionButton(icon: .gear, iconSize: 22, color: AC.ink2) { [weak self] in self?.open(.settings) }, width: 44, height: 44)
        gear.accessibilityLabel = L("tab_settings")
        let header = vstack([hstack([hug(mark), titles, spacer(), gear], spacing: 12), search], spacing: 14)
        setContent([header, placeholderBanner(), results, journey, favoritesHeader, picker, favoritesList, announcementsBox])
        stack.setCustomSpacing(14, after: header)

        NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        container.announcements.refresh()
    }

    /// Keeps the favourites picker above the keyboard
    @objc private func keyboard(_ note: Notification) {
        let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
        let overlap = note.name == UIResponder.keyboardWillHideNotification ? 0 : max(0, view.bounds.maxY - view.convert(frame, from: nil).minY - view.safeAreaInsets.bottom)
        scroll.contentInset.bottom = overlap
        scroll.scrollIndicatorInsets.bottom = overlap
    }

    override func reload() {
        let now = LocalDateTime.now
        dateLabel.text = dateLine(now)
        let searching = !search.text.trimmingCharacters(in: .whitespaces).isEmpty
        results.isHidden = !searching
        for view in [journey, favoritesHeader, favoritesList, announcementsBox] { view.isHidden = searching }
        picker.isHidden = searching || !editingFavorites
        if searching {
            results.setViews([searchResults(search.text)])
            return
        }
        journey.setViews([journeyCard(now)])
        buildFavorites(now)
        if editingFavorites { picker.reload() }
        buildAnnouncements()
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

    // MARK: - Search

    private func searchResults(_ query: String) -> UIView {
        let data = container.data
        let lines = Search.lines(data.lines, query)
        let stops = Search.stops(data.stops, query, language: Strings.language)
        let card = CardView(spacing: 4)
        if lines.isEmpty && stops.isEmpty {
            card.stack.addArrangedSubview(makeLabel(L("no_results"), 14, .regular, AC.muted))
        }
        if !lines.isEmpty {
            card.stack.addArrangedSubview(makeLabel(L("tab_lines"), 12, .semibold, AC.muted))
            for (index, line) in lines.enumerated() {
                if index > 0 { card.stack.addArrangedSubview(rowDivider(inset: 0)) }
                let row = minHeight(hstack([lineBadge(line), squeeze(makeLabel(line.name.text, 15, .medium)), spacer()], spacing: 12), 48)
                card.stack.addArrangedSubview(Tappable(row) { [weak self] in self?.open(.line(line.id, nil)) })
            }
        }
        if !stops.isEmpty {
            if !lines.isEmpty {
                card.stack.addArrangedSubview(rowDivider(inset: 0))
                card.stack.addArrangedSubview(makeLabel(L("find_stop"), 12, .semibold, AC.muted))
            }
            for (index, stop) in stops.enumerated() {
                if index > 0 { card.stack.addArrangedSubview(rowDivider(inset: 0)) }
                let here = data.linesAtStop(stop.id)
                var badges: [UIView] = here.prefix(3).map { lineBadge($0) }
                if here.count > 3 { badges.append(makeLabel("+\(here.count - 3)", 12, .medium, AC.muted)) }
                let row = minHeight(hstack([iconView(.pin, AC.muted), squeeze(makeLabel(stop.title, 15, .medium, lines: 2)), spacer(), hug(hstack(badges, spacing: 4))], spacing: 12), 52)
                card.stack.addArrangedSubview(Tappable(row) { [weak self] in self?.open(.stop(stop.id)) })
            }
        }
        return card
    }

    // MARK: - Where do you want to go?

    private func journeyCard(_ now: LocalDateTime) -> UIView {
        let card = CardView(padding: 14, spacing: 0)
        let titles = vstack([makeLabel(L("journey_title"), 16, .semibold, align: .center),
                             makeLabel(L("journey_subtitle"), 13, .regular, AC.muted, lines: 0, align: .center)], spacing: 1)
        let refresh = sized(ActionButton(icon: .refresh, iconSize: 20, color: nearby == .loading ? AC.muted : AC.link) { [weak self] in self?.locate() }, width: 44, height: 44)
        refresh.isEnabled = nearby != .loading
        refresh.accessibilityLabel = L("journey_refresh_location")
        refresh.alpha = destination == nil ? 0 : 1
        let left = sized(UIView(), width: 44, height: 44)
        card.stack.addArrangedSubview(hstack([left, titles, refresh], spacing: 0))

        let chips = Destination.allCases.map { d -> UIView in
            let on = d == destination
            let label = makeLabel(d.label, 14, on ? .semibold : .medium, on ? AC.chipOnText : AC.ink2)
            let box = padded(label, UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14))
            sized(box, height: 40)
            box.backgroundColor = on ? AC.chipOn : AC.surface
            box.rounded(20, border: on ? AC.chipOn : AC.border)
            return hug(Tappable(box) { [weak self] in
                guard let self = self else { return }
                // Tapping the selected destination again clears it
                self.destination = on ? nil : d
                self.showAll = false
                if self.destination != nil && self.nearby == .idle { self.locate() } else { self.reload() }
            })
        }
        let chipRow = hstack(chips, spacing: 8)
        card.stack.addArrangedSubview(padded(vstack([chipRow], align: .center), UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0)))

        if let destination = destination {
            plan(destination, now).forEach(card.stack.addArrangedSubview)
        }
        return card
    }

    private func plan(_ destination: Destination, _ now: LocalDateTime) -> [UIView] {
        guard let coords = nearby.coords,
              let plan = JourneyPlanner.plan(data: container.data, schedule: container.schedule, destination: destination,
                                             lat: coords.lat, lng: coords.lng, now: now)
        else {
            let message: String
            switch nearby {
            case .loading: message = "locating"
            case .denied: message = "location_denied"
            case .disabled: message = "location_unsupported"
            case .error: message = "location_error"
            default: message = "journey_need_location"
            }
            return [journeyMessage(L(message), action: nearby == .loading ? nil : L("find_nearby"))]
        }
        var views: [UIView] = []
        if plan.status != .alreadyThere && plan.status != .tooFar {
            let stop = plan.usefulStop ?? plan.nearestStop
            views.append(stopToWalkTo(stop, label: L(plan.usefulStop != nil ? "journey_useful_stop" : "journey_nearest_stop")))
            if plan.usefulStop != nil {
                let text = L("journey_nearest_no_bus", plan.nearestStop.stop.name.text, Geo.formatDistance(plan.nearestStop.distanceMeters, language: Strings.language))
                views.append(padded(makeLabel(text, 13, .regular, AC.muted, lines: 0), UIEdgeInsets(top: 2, left: 4, bottom: 0, right: 0)))
            }
        }
        switch plan.status {
        case .tooFar: views.append(journeyMessage(L("journey_too_far")))
        case .alreadyThere: views.append(journeyMessage(L("journey_already_there", plan.nearestStop.stop.name.text)))
        case .noRoute: views.append(journeyMessage(L("journey_no_route")))
        case .noMoreBuses: views.append(journeyMessage(L("journey_no_more_buses")))
        case .ready: views += options(plan)
        }
        return views
    }

    private func options(_ plan: JourneyPlan) -> [UIView] {
        let collapsed = 3
        let shown = showAll ? plan.options : Array(plan.options.prefix(collapsed))
        var rows: [UIView] = []
        for (index, option) in shown.enumerated() {
            let alight = container.data.stop(option.ride.alightStopId)?.name.text ?? option.ride.alightStopId
            rows.append(Tappable(journeyOptionRow(option, alightName: alight, highlighted: index == 0)) { [weak self] in
                self?.open(.stop(option.ride.board.stop.id))
            })
        }
        var views: [UIView] = [padded(vstack(rows, spacing: 6), UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0))]
        if plan.options.count > collapsed {
            let more = ActionButton(title: showAll ? L("journey_show_less") : L("journey_show_all", plan.options.count),
                                    icon: showAll ? .chevronUp : .chevronDown, iconSize: 14) { [weak self] in
                self?.showAll.toggle()
                self?.reload()
            }
            more.semanticContentAttribute = .forceRightToLeft
            views.append(minHeight(more, 44))
        }
        views.append(padded(makeLabel(L("journey_note"), 12, .regular, AC.muted, lines: 0),
                            UIEdgeInsets(top: plan.options.count > collapsed ? 0 : 8, left: 4, bottom: 0, right: 0)))
        return views
    }

    private func stopToWalkTo(_ stop: NearbyStop, label: String) -> UIView {
        let walk = iconView(.walk, AC.link, size: 18)
        let disc = padded(walk, UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8))
        disc.backgroundColor = AC.surfaceVariant
        disc.rounded(17)
        let texts = squeeze(vstack([makeLabel(label, 12, .regular, AC.muted), makeLabel(stop.stop.title, 15, .semibold)], spacing: 1))
        let row = minHeight(hstack([hug(disc), texts, spacer(), pill(Geo.formatDistance(stop.distanceMeters, language: Strings.language))], spacing: 10), 48)
        return Tappable(padded(row, UIEdgeInsets(top: 12, left: 0, bottom: 0, right: 0))) { [weak self] in self?.open(.stop(stop.stop.id)) }
    }

    private func journeyMessage(_ text: String, action: String? = nil) -> UIView {
        var views: [UIView] = [iconView(.location, AC.link, size: 18), squeeze(padded(makeLabel(text, 14, .regular, nil, lines: 0), UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)))]
        views.append(spacer())
        if let action = action {
            views.append(hug(ActionButton(title: action, font: .brand(15, .bold)) { [weak self] in self?.locate() }))
        }
        let box = padded(hstack(views, spacing: 10), UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 8))
        box.backgroundColor = AC.surfaceVariant
        box.rounded(14)
        return padded(box, UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0))
    }

    private func journeyOptionRow(_ option: JourneyOption, alightName: String, highlighted: Bool) -> UIView {
        let strong = highlighted ? AC.heroText : AC.onBackground
        let soft = highlighted ? AC.heroMuted : AC.muted
        let number = highlighted ? AC.heroText : AC.link
        let board = option.ride.board

        var middle: [UIView] = []
        if highlighted { middle.append(makeLabel(L("journey_fastest"), 12, .semibold, soft)) }
        middle.append(makeLabel(option.ride.line.name.text, 15, .bold, strong))
        middle.append(hstack([squeeze(makeLabel(L("journey_board", board.stop.title), 13, .regular, soft)),
                              iconView(.walk, soft, size: 12),
                              hug(makeLabel(L("journey_walk_minutes", board.walkMinutes), 13, .regular, soft))], spacing: 4))
        middle.append(makeLabel(L("journey_alight", alightName), 13, .regular, soft))

        var right: [UIView] = []
        if option.minutesUntil == 0 {
            right.append(makeLabel(L("now"), 20, .bold, strong))
        } else if option.minutesUntil > 59 {
            let hours = option.minutesUntil / 60
            let minutes = option.minutesUntil % 60
            right.append(makeLabel(minutes == 0 ? L("duration_hours", hours) : L("duration_hours_minutes", hours, minutes), highlighted ? 22 : 18, .bold, number))
        } else {
            right.append(makeLabel("\(option.minutesUntil)", highlighted ? 28 : 22, .bold, number))
            right.append(makeLabel(L("minutes_short"), 11, .regular, soft))
        }
        right.append(makeLabel(Schedule.formatMinutes(option.minutes), 12, .semibold, strong))
        if let later = option.later {
            right.append(makeLabel(L("journey_later", Schedule.formatMinutes(later)), 11, .regular, soft))
        }

        let row = hstack([lineBadge(option.ride.line, .md), squeeze(vstack(middle, spacing: 1, align: .leading)), spacer(), hug(vstack(right, align: .center))], spacing: 10)
        let box = padded(row, UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
        box.backgroundColor = highlighted ? AC.hero : AC.surfaceVariant
        box.rounded(16)
        return box
    }

    private func locate() {
        nearby = .loading
        reload()
        container.location.current { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let coords): self.nearby = .ready(coords)
            case .failure(.denied): self.nearby = .denied
            case .failure(.disabled): self.nearby = .disabled
            case .failure: self.nearby = .error
            }
            self.reload()
        }
    }

    // MARK: - Favourites

    private func buildFavorites(_ now: LocalDateTime) {
        let stops = container.settings.favorites.compactMap { container.data.stop($0) }
        var trailing: UIView?
        if !stops.isEmpty || editingFavorites {
            trailing = ActionButton(title: L(editingFavorites ? "done" : "edit")) { [weak self] in
                guard let self = self else { return }
                self.editingFavorites.toggle()
                self.view.endEditing(true)
                self.reload()
            }
        }
        favoritesHeader.setViews([sectionTitle(L("favorites"), trailing: trailing)])
        var cards: [UIView] = []
        if !editingFavorites && stops.isEmpty {
            let find = ActionButton(title: L("find_stop")) { [weak self] in
                self?.editingFavorites = true
                self?.reload()
            }
            find.contentHorizontalAlignment = .leading
            cards.append(CardView([makeLabel(L("favorites_empty"), 14, .regular, AC.muted, lines: 0), find]))
        }
        for stop in stops {
            cards.append(stopCard(stop, departures: container.schedule.nextDepartures(stop.id, now: now, limit: 3, live: container.liveTrips),
                                  now: now, host: self))
        }
        favoritesList.setViews(cards)
        favoritesList.isHidden = cards.isEmpty
    }

    // MARK: - Announcements

    private func buildAnnouncements() {
        let all = ActionButton(title: L("announcements_all"), font: .brand(15)) { [weak self] in self?.open(.announcements) }
        var views: [UIView] = [sectionTitle(L("announcements"), trailing: all)]
        if let latest = container.announcements.announcements?.first {
            views.append(Tappable(announcementRow(latest)) { [weak self] in self?.open(.announcements) })
        } else {
            views.append(makeLabel(L("announcements_none"), 14, .regular, AC.muted))
        }
        announcementsBox.setViews(views)
    }
}

/// Picking favourite stops: a search and every stop with its star
final class FavoritePickerView: UIView {
    private let settings = AppContainer.shared.settings
    private let title = makeLabel("", 14, .semibold)
    private let star = UIImageView()
    private lazy var search = SearchField(placeholder: L("search_stops"), compact: true) { [weak self] _ in self?.reload() }
    private let list = vstack([], spacing: 2)
    private let empty = makeLabel(L("no_results"), 13, .regular, AC.muted)
    private let scroll = UIScrollView()

    init() {
        super.init(frame: .zero)
        backgroundColor = AC.surface
        rounded(14, border: AC.border)
        star.contentMode = .center
        sized(star, width: 20, height: 20)
        scroll.addSubview(list)
        list.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            list.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        sized(scroll, height: 260)
        let column = vstack([hstack([hug(star), squeeze(title)], spacing: 8), search, empty, scroll], spacing: 10)
        addSubview(column)
        column.pin(to: self, UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Lists the stops again for what's typed and what's starred
    func reload() {
        let count = settings.favorites.count
        star.image = (count == 0 ? Icon.star : Icon.starFill).image(18)
        star.tintColor = count == 0 ? AC.link : AC.star
        title.text = count == 0 ? L("select_favorite_stops") : "\(L("select_favorite_stops")) (\(count))"
        let all = AppContainer.shared.data.stops
        let query = search.text
        let shown = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? all.sorted { $0.name.text < $1.name.text }
            : Search.stops(all, query, language: Strings.language)
        empty.isHidden = !shown.isEmpty
        scroll.isHidden = shown.isEmpty
        list.setViews(shown.map { stop in
            let on = settings.isFavorite(stop.id)
            let row = minHeight(hstack([squeeze(makeLabel(stop.title, 14, on ? .semibold : .regular, lines: 0)), spacer(),
                                        iconView(on ? .starFill : .star, on ? AC.star : AC.muted, size: 18)], spacing: 8), 40)
            return Tappable(padded(row, UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8))) { [weak self] in
                self?.settings.toggleFavorite(stop.id)
                self?.reload()
            }
        })
    }
}
