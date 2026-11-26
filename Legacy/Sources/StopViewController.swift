import UIKit

/// Reads a stop's next departures out loud when they change and the voice is on. The stop page and the
/// map's stop card each have one.
final class StopVoice {
    private let announcer = Announcer()
    private var lastSpoken = ""
    /// The speaker button's choice; nil follows Settings
    var choice: Bool?

    /// On for this stop
    var isOn: Bool { choice ?? AppContainer.shared.settings.voice }

    /// The phone has a voice for the app's language
    var hasVoice: Bool { announcer.hasVoice }

    /// Speaks when what would be said changed: when the stop opens or the voice is turned on, when the first
    /// bus leaves, and once more when the next one is two minutes away. Not every minute.
    func update(stopName: String, departures: [Departure], now: LocalDateTime) {
        let spoken = Array(departures.prefix(3))
        let nextIsClose = spoken.first.map { $0.dayOffset == 0 && Schedule.minutesUntil($0, now: now) <= 2 } ?? false
        let key = "\(isOn)|\(nextIsClose)|" + spoken.map { "\($0.line.id)-\($0.direction.id)-\($0.minutes)-\($0.dayOffset)" }.joined(separator: ",")
        guard key != lastSpoken else { return }
        lastSpoken = key
        if isOn {
            announcer.speak(Announcer.announcement(stopName: stopName, departures: spoken, now: now))
        } else {
            announcer.stop()
        }
    }

    /// Goes quiet
    func stop() { announcer.stop() }

    /// The speaker button: turns the voice on or off for this stop, and says when the phone has no voice
    func button(host: UIViewController, changed: @escaping () -> Void) -> UIButton {
        let button = ActionButton(icon: isOn ? .speakerOn : .speakerOff, iconSize: 22, color: isOn ? AC.link : AC.muted) {}
        button.setAction { [weak self, weak host, weak button] in
            guard let self = self else { return }
            self.choice = !self.isOn
            button?.setImage((self.isOn ? Icon.speakerOn : Icon.speakerOff).image(22), for: .normal)
            button?.tintColor = self.isOn ? AC.link : AC.muted
            button?.accessibilityLabel = L(self.isOn ? "voice_mute" : "voice_unmute")
            if self.isOn && !self.hasVoice {
                let alert = UIAlertController(title: L("voice_missing"), message: nil, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: L("close"), style: .cancel))
                host?.present(alert, animated: true)
            }
            changed()
        }
        button.accessibilityLabel = L(isOn ? "voice_mute" : "voice_unmute")
        return sized(button, width: 40, height: 44)
    }
}

/// A stop's next departures, filterable by line, read out loud when voice is on
final class StopViewController: ScrollScreen {
    private let stopId: String
    private var lineFilter: String?
    private let voice = StopVoice()
    private let container = AppContainer.shared

    init(stopId: String) {
        self.stopId = stopId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        // The chips scroll edge to edge, so the column has no side margins of its own
        contentInsets = UIEdgeInsets(top: 4, left: 0, bottom: 16, right: 0)
        super.viewDidLoad()
        let speaker = UIBarButtonItem(customView: voice.button(host: self) { [weak self] in self?.reload() })
        let mapButton = ActionButton(icon: .map, iconSize: 22, color: AC.link) { [weak self] in
            guard let self = self else { return }
            self.open(.map(line: nil, stop: self.stopId))
        }
        mapButton.accessibilityLabel = L("show_on_map")
        let star = UIBarButtonItem(customView: favoriteButton(stopId, tint: AC.link))
        navigationItem.rightBarButtonItems = [star, UIBarButtonItem(customView: sized(mapButton, width: 40, height: 44)), speaker]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        container.announcements.refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        voice.stop()
    }

    override func reload() {
        guard let stop = container.data.stop(stopId) else { return }
        let now = LocalDateTime.now
        let schedule = container.schedule
        let lines = container.data.linesAtStop(stop.id)
        let departures = Array(schedule.nextDepartures(stop.id, now: now, limit: 40, live: container.liveTrips)
            .filter { lineFilter == nil || $0.line.id == lineFilter }
            .prefix(12))
        // The bus that just left by the timetable, unless it's running late and still on its way here
        let previous = schedule.previousDeparture(stop.id, now: now)
            .flatMap { p in lineFilter == nil || p.line.id == lineFilter ? p : nil }
            .flatMap { p in departures.contains { $0.live && $0.line.id == p.line.id && $0.direction.id == p.direction.id && $0.tripStart == p.tripStart } ? nil : p }
        let notice = container.announcements.announcements?.first { $0.isActive(today: now.date, now: Date()) }

        let side = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        var views: [UIView?] = []
        views.append(padded(vstack([makeLabel(stop.title, 22, .semibold, lines: 0),
                                    makeLabel(L("stop_code", stop.id) + " · " + L("lines_count", lines.count), 13, .regular, AC.muted)], spacing: 1), side))
        if lines.count > 1 {
            var chips: [UIView] = [chip(selected: lineFilter == nil, [makeLabel(L("all_filter"), 13, .semibold, lineFilter == nil ? AC.chipOnText : AC.ink2)],
                                        horizontalPadding: 14) { [weak self] in
                self?.lineFilter = nil
                self?.reload()
            }]
            for line in lines {
                let on = lineFilter == line.id
                chips.append(chip(selected: on, [lineBadge(line), makeLabel(line.name.text, 13, .semibold, on ? AC.chipOnText : AC.ink2)], horizontalPadding: 10) { [weak self] in
                    self?.lineFilter = on ? nil : line.id
                    self?.reload()
                })
            }
            views.append(sized(horizontalScroller(chips, spacing: 8, inset: 16), height: 36))
        }
        var column: [UIView?] = [placeholderBanner()]
        if let notice = notice {
            let row = hstack([iconView(.warning, AC.bannerText, size: 20),
                              squeeze(vstack([makeLabel(notice.title, 14, .semibold, AC.bannerText, lines: 2),
                                              makeLabel(L("notice_details"), 12, .regular, AC.bannerText)], spacing: 1)),
                              spacer(), iconView(.chevronRight, AC.bannerText, size: 14)], spacing: 12)
            let box = padded(row, UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
            box.backgroundColor = AC.bannerBg
            box.rounded(12)
            column.append(Tappable(box) { [weak self] in self?.open(.announcements) })
        }
        column.append(padded(hstack([makeLabel(L("next_departures"), 15, .semibold), spacer(),
                                     hug(makeLabel(schedule.serviceDay(for: now.date).label, 12, .regular, AC.muted))], align: .lastBaseline),
                             UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)))
        column.append(CardView([departureList(departures, now: now, previous: previous, host: self)]))
        views.append(padded(vstack(column.compactMap { $0 }, spacing: 12), side))
        setContent(views)

        voice.update(stopName: stop.name.text, departures: departures, now: now)
    }
}
