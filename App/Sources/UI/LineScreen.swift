import SwiftUI

/// A line's full timetable from its first stop, for each direction and kind of day, in the current season
struct LineScreen: View {
    /// `Line.id`
    let lineId: String
    /// The direction to open on; nil opens the first
    let initialDirectionId: String?
    @EnvironmentObject private var container: AppContainer
    @State private var directionId: String?
    @State private var service: ServiceDay?

    var body: some View {
        if let line = container.data.line(lineId) {
            Ticking { now in
                content(line, now)
            }
            .background(AC.background)
            // The line's badge and name are at the top of the page already
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.map(line: line.id, stop: nil)) {
                        Image(systemName: "map")
                    }
                    .accessibilityLabel(L("show_on_map"))
                }
            }
        }
    }

    private func content(_ line: Line, _ now: LocalDateTime) -> some View {
        let schedule = container.schedule
        let today = now.date
        let todayService = schedule.timetableDay(line.id, today)
        let season = schedule.season(for: today)
        let direction = line.direction(directionId ?? initialDirectionId)!
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
        let lineColor = Color(hexString: line.color)
        let lineText = Color(hexString: line.textColor)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    LineBadge(line: line, size: .lg)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.name.text).font(.brand(20, .semibold)).lineLimit(2)
                        if let summary = summary(deps) { Text(summary).font(.brand(13)).foregroundStyle(AC.muted) }
                    }
                }
                .padding(.top, 4)
                if line.directions.count > 1 {
                    Segmented(options: line.directions.map { (value: $0.id, label: L("towards_cap", $0.headsign.text)) },
                              selected: Binding(get: { direction.id }, set: { directionId = $0 }))
                }
                PlaceholderBanner(visible: container.data.meta.placeholder)
                ChipRow(options: ServiceDay.allCases
                            .filter { $0 != .wednesday || schedule.hasWednesday(line.id) }
                            .map { (value: $0, label: $0.label) },
                        selected: Binding(get: { selected }, set: { service = $0 }))
                if let firstStop {
                    Text(L("departures_from", firstStop.name.text) + " · " + season.label)
                        .font(.brand(13))
                        .foregroundStyle(AC.muted)
                        .padding(.horizontal, 4)
                }
                AppCard(padding: 0, spacing: 0) {
                    if deps.isEmpty {
                        Text(L("no_service")).font(.brand(14)).foregroundStyle(AC.muted).padding(.horizontal, 16)
                    } else {
                        ForEach(Array(shown.enumerated()), id: \.element) { index, minutes in
                            let past = isToday && minutes < nowMin
                            let next = minutes == nextMin
                            if index > 0 && !next && shown[index - 1] != nextMin { Rectangle().fill(AC.divider).frame(height: 1) }
                            HStack {
                                Text(Schedule.formatMinutes(minutes))
                                    .font(.brand(next ? 18 : 16, next ? .bold : .medium))
                                    .foregroundStyle(next ? lineText : past ? AC.muted.opacity(0.7) : AC.onBackground)
                                Spacer()
                                if let note = notes[minutes] { NoteButton(note: note, tint: next ? lineText : AC.link) }
                                // Only the one that just left and the next one say anything
                                if past {
                                    Text(L("departed_short")).font(.brand(12)).foregroundStyle(AC.muted)
                                } else if next {
                                    let mins = minutes - nowMin
                                    Text(mins <= 0 ? L("now") : L("in_min", mins)).font(.brand(13, .semibold)).foregroundStyle(lineText)
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: next ? 52 : 46)
                            .background(next ? lineColor : Color.clear)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                if doneToday {
                    Text(L("no_more_today")).font(.brand(13)).foregroundStyle(AC.muted).padding(.horizontal, 4)
                } else if let last = deps.last {
                    Text(L("last_trip_of_day", Schedule.formatMinutes(last))).font(.brand(13)).foregroundStyle(AC.muted).padding(.horizontal, 4)
                }
                NavigationLink(value: Route.routeStops(line.id, direction.id)) {
                    RouteNowCard(direction: direction,
                                 firstName: firstStop?.name.text ?? "",
                                 lastName: container.data.stop(direction.stops.last?.stop)?.name.text ?? "",
                                 positions: schedule.positionsOnRoute(line, direction, now: now),
                                 lineColor: lineColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    /// "Every 20 min · 07:00 to 20:15", or just the first and last time when the gaps differ
    private func summary(_ deps: [Int]) -> String? {
        guard let first = deps.first, let last = deps.last else { return nil }
        let span = L("first_last", Schedule.formatMinutes(first), Schedule.formatMinutes(last))
        let gaps = Set(zip(deps, deps.dropFirst()).map { $1 - $0 })
        if gaps.count == 1, let gap = gaps.first { return L("every_min", gap) + " · " + span }
        return span
    }
}

/// The direction as a strip of stops, with the buses the timetable puts on it now
private struct RouteNowCard: View {
    let direction: Direction
    let firstName: String
    let lastName: String
    let positions: [Double]
    let lineColor: Color

    var body: some View {
        AppCard {
            HStack(spacing: 8) {
                Text(L("on_route_now")).font(.brand(15, .semibold))
                Spacer()
                Text(positions.isEmpty ? L("no_bus_on_route") : LP("buses_on_route", positions.count))
                    .font(.brand(13))
                    .foregroundStyle(AC.muted)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AC.muted)
            }
            GeometryReader { geo in
                let count = direction.stops.count
                let r: CGFloat = 6
                let left = r
                let right = geo.size.width - r
                let y = geo.size.height / 2
                let x = { (p: Double) -> CGFloat in count < 2 ? left : left + (right - left) * CGFloat(p / Double(count - 1)) }
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: left, y: y))
                        path.addLine(to: CGPoint(x: right, y: y))
                    }
                    .stroke(lineColor, lineWidth: 4)
                    ForEach(0..<count, id: \.self) { i in
                        let end = i == 0 || i == count - 1
                        Circle()
                            .fill(end ? lineColor : AC.surface)
                            .overlay { if !end { Circle().strokeBorder(lineColor, lineWidth: 3) } }
                            .frame(width: r * 2, height: r * 2)
                            .position(x: x(Double(i)), y: y)
                    }
                    ForEach(positions.indices, id: \.self) { i in
                        BusMarker().position(x: x(positions[i]), y: y)
                    }
                }
            }
            .frame(height: 30)
            HStack {
                Text(firstName).lineLimit(1)
                Spacer()
                Text(lastName).lineLimit(1)
            }
            .font(.brand(12))
            .foregroundStyle(AC.muted)
            if !positions.isEmpty {
                Text(L("buses_estimated")).font(.brand(12)).foregroundStyle(AC.muted)
            }
        }
    }
}
