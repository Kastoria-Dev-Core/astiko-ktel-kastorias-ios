import SwiftUI

/// Every stop of a direction, when the next bus reaches each, and where the buses are between them
struct RouteStopsScreen: View {
    /// `Line.id`
    let lineId: String
    /// The direction to open on; nil opens the first
    let initialDirectionId: String?
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @State private var directionId: String?

    private let rowHeight: CGFloat = 52

    var body: some View {
        if let line = container.data.line(lineId) {
            Ticking { now in
                content(line, now)
            }
            .background(AC.background)
            .navigationTitle(L("stops"))
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
        let direction = line.direction(directionId ?? initialDirectionId)!
        let stops = direction.stops
        let arrivals = container.schedule.nextArrivals(line, direction, now: now)
        let positions = container.schedule.positionsOnRoute(line, direction, now: now)
        let nowMin = Schedule.minutesOfDay(now)
        let lineColor = Color(hexString: line.color)
        let trip = stops.last.map(\.offset) ?? 0

        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    LineBadge(line: line, size: .lg)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(line.name.text).font(.brand(18, .semibold)).lineLimit(2)
                        Text(L("stops_count", stops.count) + (trip > 0 ? " · " + L("trip_minutes", trip) : ""))
                            .font(.brand(13))
                            .foregroundStyle(AC.muted)
                    }
                }
                .padding(.top, 4)
                if line.directions.count > 1 {
                    Segmented(options: line.directions.map { (value: $0.id, label: L("towards_cap", $0.headsign.text)) },
                              selected: Binding(get: { direction.id }, set: { directionId = $0 }))
                }
                Text(L("next_bus_each_stop")).font(.brand(13)).foregroundStyle(AC.muted).padding(.horizontal, 4)
                AppCard(padding: 0, spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.offset) { i, ds in
                        if let stop = container.data.stop(ds.stop) {
                            if i > 0 { RowDivider(inset: 48) }
                            NavigationLink(value: Route.stop(stop.id)) {
                                row(stop: stop, index: i, count: stops.count, arrival: i < arrivals.count ? arrivals[i] : nil,
                                    nowMin: nowMin, lineColor: lineColor, positions: positions)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !positions.isEmpty {
                    Text(L("buses_estimated")).font(.brand(12)).foregroundStyle(AC.muted).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func row(stop: Stop, index i: Int, count: Int, arrival: Int?, nowMin: Int, lineColor: Color, positions: [Double]) -> some View {
        let first = i == 0
        let last = i == count - 1
        // Buses between the previous stop and this one (or at this one), drawn on this row
        let busesHere = positions.filter { p in first ? p == 0 : Int(p.rounded(.up)) == i && p > Double(i - 1) }
        return HStack(spacing: 0) {
            ZStack {
                // The line runs on through the divider, so it looks continuous
                VStack(spacing: 0) {
                    Rectangle().fill(first ? Color.clear : lineColor).frame(width: 4)
                    Rectangle().fill(last ? Color.clear : lineColor).frame(width: 4)
                }
                Circle()
                    .fill(first || last ? lineColor : AC.surface)
                    .overlay { if !(first || last) { Circle().strokeBorder(lineColor, lineWidth: 3) } }
                    .frame(width: first || last ? 16 : 12, height: first || last ? 16 : 12)
                ForEach(busesHere.indices, id: \.self) { k in
                    // 0 is this row's stop, 1 the previous stop one row up
                    BusMarker().offset(y: -CGFloat(Double(i) - busesHere[k]) * (rowHeight + 1))
                }
            }
            .frame(width: 48, height: rowHeight)
            .zIndex(busesHere.isEmpty ? 0 : 1)
            HStack(spacing: 6) {
                Text(stop.title).font(.brand(15, first || last ? .semibold : .regular)).lineLimit(1)
                if settings.isFavorite(stop.id) {
                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(AC.star)
                }
            }
            Spacer(minLength: 8)
            arrivalLabel(arrival, nowMin: nowMin, isLast: last)
        }
        .padding(.trailing, 16)
        .frame(height: rowHeight)
        .contentShape(Rectangle())
    }

    /// Within the hour: minutes, with the clock time under them. Later: the clock time. None left today: a dash.
    @ViewBuilder
    private func arrivalLabel(_ arrival: Int?, nowMin: Int, isLast: Bool) -> some View {
        if let arrival {
            let mins = arrival - nowMin
            VStack(alignment: .trailing, spacing: 0) {
                if mins < 60 {
                    Text(mins <= 0 ? L("now") : L("in_min", mins)).font(.brand(15, .semibold))
                    Text(Schedule.formatMinutes(arrival)).font(.brand(12)).foregroundStyle(AC.muted)
                } else {
                    Text(Schedule.formatMinutes(arrival)).font(.brand(15, isLast ? .medium : .regular)).foregroundStyle(AC.ink2)
                }
            }
        } else {
            Text(L("none_expected")).font(.brand(12)).foregroundStyle(AC.muted)
        }
    }
}
