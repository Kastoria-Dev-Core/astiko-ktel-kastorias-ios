import SwiftUI

/// Every line in one list: number, name, where it goes, and when the next bus leaves
struct LinesScreen: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        Ticking { now in
            ScrollView {
                VStack(spacing: 12) {
                    PlaceholderBanner(visible: container.data.meta.placeholder)
                    AppCard(padding: 0, spacing: 0) {
                        ForEach(Array(container.data.lines.enumerated()), id: \.element.id) { index, line in
                            if index > 0 { RowDivider(inset: 66) }
                            NavigationLink(value: Route.line(line.id, nil)) {
                                row(line, now)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(AC.background)
        .navigationTitle(L("tab_lines"))
        .navigationBarTitleDisplayMode(.large)
    }

    private func row(_ line: Line, _ now: LocalDateTime) -> some View {
        let data = container.data
        // The soonest bus of either direction, today
        let next = line.directions.compactMap { container.schedule.nextTrip(line, $0, now: now) }.min()
        let route = line.directions.first.map { data.directionStops(line, $0.id) } ?? []
        return HStack(spacing: 14) {
            LineBadge(line: line, size: .md)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.name.text).font(.brand(15, .medium)).lineLimit(2)
                // Where the line starts and where it ends
                Text(route.count > 1 ? "\(route[0].name.text) - \(route[route.count - 1].name.text)" : line.name.text)
                    .font(.brand(13))
                    .foregroundStyle(AC.muted)
                    .lineLimit(2)
            }
            .multilineTextAlignment(.leading)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(L("next_label")).font(.brand(12)).foregroundStyle(AC.muted)
                Text(next.map(Schedule.formatMinutes) ?? "–")
                    .font(.brand(15, .semibold))
                    .accessibilityLabel(next.map(Schedule.formatMinutes) ?? L("none_today"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }
}
