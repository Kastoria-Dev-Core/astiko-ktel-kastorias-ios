import UIKit

/// Every line in one list: number, name, where it goes, and when the next bus leaves
final class LinesViewController: ScrollScreen {
    private let container = AppContainer.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("tab_lines")
        navigationItem.largeTitleDisplayMode = .always
    }

    override func reload() {
        let now = LocalDateTime.now
        let card = CardView(padding: 0, spacing: 0, vertical: 0)
        for (index, line) in container.data.lines.enumerated() {
            if index > 0 { card.stack.addArrangedSubview(rowDivider(inset: 66)) }
            card.stack.addArrangedSubview(Tappable(row(line, now)) { [weak self] in self?.open(.line(line.id, nil)) })
        }
        setContent([placeholderBanner(), card])
    }

    private func row(_ line: Line, _ now: LocalDateTime) -> UIView {
        let data = container.data
        let next = line.directions.compactMap { container.schedule.nextTrip(line, $0, now: now) }.min()
        let route = line.directions.first.map { data.directionStops(line, $0.id) } ?? []
        let ends = route.count > 1 ? "\(route[0].name.text) - \(route[route.count - 1].name.text)" : line.name.text
        let texts = squeeze(vstack([makeLabel(line.name.text, 15, .medium, lines: 2), makeLabel(ends, 13, .regular, AC.muted, lines: 2)], spacing: 1))
        let time = makeLabel(next.map(Schedule.formatMinutes) ?? "–", 15, .semibold)
        time.accessibilityLabel = next.map(Schedule.formatMinutes) ?? L("none_today")
        let right = hug(vstack([makeLabel(L("next_label"), 12, .regular, AC.muted), time], spacing: 1, align: .trailing))
        let row = minHeight(hstack([lineBadge(line, .md), texts, spacer(min: 4), right], spacing: 14), 64)
        return padded(row, UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16))
    }
}

/// The map button in the navigation bar of a line's screens
private func mapButton(_ host: UIViewController, line: String?, stop: String?) -> UIBarButtonItem {
    let item = UIBarButtonItem(image: Icon.map.image(22), style: .plain, target: nil, action: nil)
    let button = ActionButton(icon: .map, iconSize: 22, color: AC.link) { [weak host] in host?.open(.map(line: line, stop: stop)) }
    sized(button, width: 40, height: 40)
    button.accessibilityLabel = L("show_on_map")
    item.customView = button
    return item
}

/// A line's full timetable from its first stop, for each direction and kind of day, in the current season
final class LineViewController: ScrollScreen {
    private let lineId: String
    private var directionId: String?
    private var service: ServiceDay?
    private let container = AppContainer.shared

    init(lineId: String, directionId: String?) {
        self.lineId = lineId
        self.directionId = directionId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.rightBarButtonItem = mapButton(self, line: lineId, stop: nil)
    }

    override func reload() {
        guard let line = container.data.line(lineId), let direction = line.direction(directionId) else { return }
        let now = LocalDateTime.now
        let schedule = container.schedule
        let today = now.date
        let todayService = schedule.timetableDay(line.id, today)
        let season = schedule.season(for: today)
        let selected = service ?? todayService
        let deps = schedule.departures(line.id, direction.id, selected, season)
        let notes = schedule.notes(line.id, direction.id, selected, season)
        let isToday = selected == todayService
        let nowMin = Schedule.minutesOfDay(now)
        let nextIndex = isToday ? deps.firstIndex { $0 >= nowMin } : nil
        let doneToday = isToday && !deps.isEmpty && nextIndex == nil
        // Today: departed trips are hidden, except the one that just left (greyed out)
        let shown: [Int] = !isToday ? deps : doneToday ? Array(deps.suffix(1)) : Array(deps.dropFirst(max(0, (nextIndex ?? 0) - 1)))
        let nextMin = nextIndex.map { deps[$0] }
        let firstStop = container.data.stop(direction.stops.first?.stop)
        let lineColor = UIColor(hexString: line.color)
        let lineText = UIColor(hexString: line.textColor)

        var views: [UIView?] = []
        var titles: [UIView] = [makeLabel(line.name.text, 20, .semibold, lines: 2)]
        if let summary = summary(deps) { titles.append(makeLabel(summary, 13, .regular, AC.muted, lines: 0)) }
        views.append(hstack([lineBadge(line, .lg), squeeze(vstack(titles, spacing: 1)), spacer()], spacing: 10))
        if line.directions.count > 1 {
            views.append(SegmentedView(options: line.directions.map { (value: $0.id, label: L("towards_cap", $0.headsign.text)) },
                                       selected: direction.id) { [weak self] id in
                self?.directionId = id
                self?.reload()
            })
        }
        views.append(placeholderBanner())
        let days = ServiceDay.allCases.filter { $0 != .wednesday || schedule.hasWednesday(line.id) }
        views.append(sized(horizontalScroller(days.map { day in
            textChip(day.label, selected: day == selected) { [weak self] in
                self?.service = day
                self?.reload()
            }
        }), height: 36))
        if let firstStop = firstStop {
            views.append(padded(makeLabel(L("departures_from", firstStop.name.text) + " · " + season.label, 13, .regular, AC.muted, lines: 0),
                                UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)))
        }

        let card = CardView(padding: 0, spacing: 0, vertical: 0)
        card.clipsToBounds = true
        if deps.isEmpty {
            card.stack.addArrangedSubview(padded(makeLabel(L("no_service"), 14, .regular, AC.muted), UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)))
        } else {
            for (index, minutes) in shown.enumerated() {
                let past = isToday && minutes < nowMin
                let next = minutes == nextMin
                if index > 0 && !next && shown[index - 1] != nextMin { card.stack.addArrangedSubview(rowDivider(inset: 0)) }
                var row: [UIView] = [makeLabel(Schedule.formatMinutes(minutes), next ? 18 : 16, next ? .bold : .medium,
                                               next ? lineText : past ? AC.muted.withAlphaComponent(0.7) : AC.onBackground), spacer()]
                if let note = notes[minutes] { row.append(noteButton(note, tint: next ? lineText : AC.link, host: self)) }
                if past {
                    row.append(makeLabel(L("departed_short"), 12, .regular, AC.muted))
                } else if next {
                    let mins = minutes - nowMin
                    row.append(makeLabel(mins <= 0 ? L("now") : L("in_min", mins), 13, .semibold, lineText))
                }
                let box = padded(minHeight(hstack(row), next ? 52 : 46), UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16))
                box.backgroundColor = next ? lineColor : .clear
                card.stack.addArrangedSubview(box)
            }
        }
        views.append(card)
        let footer: String? = doneToday ? L("no_more_today") : deps.last.map { L("last_trip_of_day", Schedule.formatMinutes($0)) }
        if let footer = footer {
            views.append(padded(makeLabel(footer, 13, .regular, AC.muted, lines: 0), UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)))
        }
        let routeCard = routeNowCard(direction: direction,
                                     firstName: firstStop?.name.text ?? "",
                                     lastName: container.data.stop(direction.stops.last?.stop)?.name.text ?? "",
                                     positions: schedule.positionsOnRoute(line, direction, now: now),
                                     lineColor: lineColor)
        let directionId = direction.id
        views.append(Tappable(routeCard) { [weak self] in
            guard let self = self else { return }
            self.open(.routeStops(self.lineId, directionId))
        })
        setContent(views)
    }

    /// "Every 20 min · 07:00 to 20:15", or just the first and last time when the gaps differ
    private func summary(_ deps: [Int]) -> String? {
        guard let first = deps.first, let last = deps.last else { return nil }
        let span = L("first_last", Schedule.formatMinutes(first), Schedule.formatMinutes(last))
        let gaps = Set(zip(deps, deps.dropFirst()).map { $1 - $0 })
        if gaps.count == 1, let gap = gaps.first { return L("every_min", gap) + " · " + span }
        return span
    }

    private func routeNowCard(direction: Direction, firstName: String, lastName: String, positions: [Double], lineColor: UIColor) -> UIView {
        let header = hstack([makeLabel(L("on_route_now"), 15, .semibold), spacer(),
                             hug(makeLabel(positions.isEmpty ? L("no_bus_on_route") : LP("buses_on_route", positions.count), 13, .regular, AC.muted)),
                             iconView(.chevronRight, AC.muted, size: 14)], spacing: 8)
        let strip = RouteStripView(count: direction.stops.count, positions: positions, color: lineColor)
        sized(strip, height: 30)
        let ends = hstack([squeeze(makeLabel(firstName, 12, .regular, AC.muted)), spacer(), squeeze(makeLabel(lastName, 12, .regular, AC.muted, align: .right))])
        var views: [UIView] = [header, strip, ends]
        if !positions.isEmpty { views.append(makeLabel(L("buses_estimated"), 12, .regular, AC.muted, lines: 0)) }
        return CardView(views)
    }
}

/// A direction as a strip of stops, with the buses the timetable puts on it now
final class RouteStripView: UIView {
    private let count: Int
    private let positions: [Double]
    private let color: UIColor
    private var markers: [UIView] = []

    init(count: Int, positions: [Double], color: UIColor) {
        self.count = count
        self.positions = positions
        self.color = color
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        for _ in positions {
            let marker = busMarker()
            marker.translatesAutoresizingMaskIntoConstraints = true
            addSubview(marker)
            markers.append(marker)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    private func x(_ p: Double) -> CGFloat {
        let r: CGFloat = 6
        let left = r
        let right = bounds.width - r
        return count < 2 ? left : left + (right - left) * CGFloat(p / Double(count - 1))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (marker, p) in zip(markers, positions) {
            marker.frame = CGRect(x: x(p) - 13, y: bounds.midY - 13, width: 26, height: 26)
        }
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        let y = bounds.midY
        let r: CGFloat = 6
        let line = UIBezierPath()
        line.move(to: CGPoint(x: r, y: y))
        line.addLine(to: CGPoint(x: bounds.width - r, y: y))
        line.lineWidth = 4
        color.setStroke()
        line.stroke()
        for i in 0..<count {
            let end = i == 0 || i == count - 1
            let dot = UIBezierPath(ovalIn: CGRect(x: x(Double(i)) - r, y: y - r, width: r * 2, height: r * 2))
            if end {
                color.setFill()
                dot.fill()
            } else {
                AC.surface.setFill()
                dot.fill()
                let ring = UIBezierPath(ovalIn: CGRect(x: x(Double(i)) - r + 1.5, y: y - r + 1.5, width: r * 2 - 3, height: r * 2 - 3))
                ring.lineWidth = 3
                color.setStroke()
                ring.stroke()
            }
        }
    }
}

/// Every stop of a direction, when the next bus reaches each, and where the buses are between them
final class RouteStopsViewController: ScrollScreen {
    private let lineId: String
    private var directionId: String?
    private let container = AppContainer.shared
    private let rowHeight: CGFloat = 52

    init(lineId: String, directionId: String?) {
        self.lineId = lineId
        self.directionId = directionId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("stops")
        navigationItem.rightBarButtonItem = mapButton(self, line: lineId, stop: nil)
    }

    override func reload() {
        guard let line = container.data.line(lineId), let direction = line.direction(directionId) else { return }
        let now = LocalDateTime.now
        let stops = direction.stops
        let arrivals = container.schedule.nextArrivals(line, direction, now: now)
        let positions = container.schedule.positionsOnRoute(line, direction, now: now)
        let nowMin = Schedule.minutesOfDay(now)
        let lineColor = UIColor(hexString: line.color)
        let trip = stops.last.map { $0.offset } ?? 0

        var views: [UIView] = []
        let subtitle = L("stops_count", stops.count) + (trip > 0 ? " · " + L("trip_minutes", trip) : "")
        views.append(hstack([lineBadge(line, .lg), squeeze(vstack([makeLabel(line.name.text, 18, .semibold, lines: 2), makeLabel(subtitle, 13, .regular, AC.muted)], spacing: 1)), spacer()], spacing: 10))
        if line.directions.count > 1 {
            views.append(SegmentedView(options: line.directions.map { (value: $0.id, label: L("towards_cap", $0.headsign.text)) },
                                       selected: direction.id) { [weak self] id in
                self?.directionId = id
                self?.reload()
            })
        }
        views.append(padded(makeLabel(L("next_bus_each_stop"), 13, .regular, AC.muted, lines: 0), UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)))
        let card = CardView(padding: 0, spacing: 0, vertical: 0)
        var markerRows: [UIView] = []
        for (i, ds) in stops.enumerated() {
            guard let stop = container.data.stop(ds.stop) else { continue }
            if i > 0 { card.stack.addArrangedSubview(rowDivider(inset: 48)) }
            let (row, hasBus) = self.row(stop: stop, index: i, count: stops.count, arrival: i < arrivals.count ? arrivals[i] : nil,
                                         nowMin: nowMin, lineColor: lineColor, positions: positions)
            let tappable = Tappable(row) { [weak self] in self?.open(.stop(stop.id)) }
            card.stack.addArrangedSubview(tappable)
            if hasBus { markerRows.append(tappable) }
        }
        // Rows with a bus go on top, so a marker drawn up into the row above isn't covered
        markerRows.forEach { card.stack.bringSubviewToFront($0) }
        views.append(card)
        if !positions.isEmpty {
            views.append(padded(makeLabel(L("buses_estimated"), 12, .regular, AC.muted, lines: 0), UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)))
        }
        setContent(views)
    }

    private func row(stop: Stop, index i: Int, count: Int, arrival: Int?, nowMin: Int, lineColor: UIColor, positions: [Double]) -> (UIView, Bool) {
        let first = i == 0
        let last = i == count - 1
        let busesHere = positions.filter { p in first ? p == 0 : Int(p.rounded(.up)) == i && p > Double(i - 1) }

        let rail = UIView()
        rail.clipsToBounds = false
        sized(rail, width: 48, height: rowHeight)
        let top = UIView()
        top.backgroundColor = first ? .clear : lineColor
        let bottom = UIView()
        bottom.backgroundColor = last ? .clear : lineColor
        let dotSize: CGFloat = first || last ? 16 : 12
        let dot = UIView()
        dot.backgroundColor = first || last ? lineColor : AC.surface
        dot.rounded(dotSize / 2, border: first || last ? nil : lineColor, width: 3)
        for v in [top, bottom, dot] {
            v.translatesAutoresizingMaskIntoConstraints = false
            rail.addSubview(v)
        }
        NSLayoutConstraint.activate([
            top.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
            top.widthAnchor.constraint(equalToConstant: 4),
            // Past the divider, so the line looks continuous
            top.topAnchor.constraint(equalTo: rail.topAnchor, constant: -1),
            top.bottomAnchor.constraint(equalTo: rail.centerYAnchor),
            bottom.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
            bottom.widthAnchor.constraint(equalToConstant: 4),
            bottom.topAnchor.constraint(equalTo: rail.centerYAnchor),
            bottom.bottomAnchor.constraint(equalTo: rail.bottomAnchor),
            dot.centerXAnchor.constraint(equalTo: rail.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: rail.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: dotSize),
            dot.heightAnchor.constraint(equalToConstant: dotSize),
        ])
        for p in busesHere {
            // 0 is this row's stop, 1 the previous stop one row up
            let marker = busMarker()
            rail.addSubview(marker)
            marker.centerXAnchor.constraint(equalTo: rail.centerXAnchor).isActive = true
            marker.centerYAnchor.constraint(equalTo: rail.centerYAnchor, constant: -CGFloat(Double(i) - p) * (rowHeight + 1)).isActive = true
        }

        var name: [UIView] = [squeeze(makeLabel(stop.title, 15, first || last ? .semibold : .regular))]
        if AppContainer.shared.settings.isFavorite(stop.id) { name.append(iconView(.starFill, AC.star, size: 13)) }

        let arrivalView: UIView
        if let arrival = arrival {
            let mins = arrival - nowMin
            if mins < 60 {
                arrivalView = vstack([makeLabel(mins <= 0 ? L("now") : L("in_min", mins), 15, .semibold),
                                      makeLabel(Schedule.formatMinutes(arrival), 12, .regular, AC.muted)], align: .trailing)
            } else {
                arrivalView = makeLabel(Schedule.formatMinutes(arrival), 15, last ? .medium : .regular, AC.ink2)
            }
        } else {
            arrivalView = makeLabel(L("none_expected"), 12, .regular, AC.muted)
        }
        let row = hstack([rail, squeeze(hstack(name, spacing: 6)), spacer(min: 8), hug(arrivalView)], spacing: 0)
        sized(row, height: rowHeight)
        row.clipsToBounds = false
        return (padded(row, UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 16)), !busesHere.isEmpty)
    }
}
