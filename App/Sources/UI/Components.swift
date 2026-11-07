import SwiftUI

/// The size of a line badge: a small rounded rectangle, never a circle or a pill
enum BadgeSize {
    case sm, md, lg

    var height: CGFloat { self == .sm ? 24 : self == .md ? 28 : 32 }
    var minWidth: CGFloat { self == .sm ? 34 : self == .md ? 40 : 44 }
    var font: CGFloat { self == .sm ? 13 : self == .md ? 15 : 17 }
    var radius: CGFloat { self == .sm ? 6 : self == .md ? 7 : 8 }
}

/// A line's number in its colour. School lines are outlined so they read as a different kind of service.
struct LineBadge: View {
    let line: Line
    var size: BadgeSize = .sm

    var body: some View {
        let color = Color(hexString: line.color)
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        Text(line.number.count < 2 ? "0" + line.number : line.number)
            .font(.brand(size.font, .bold))
            .lineLimit(1)
            .foregroundStyle(line.school ? AC.onBackground : Color(hexString: line.textColor))
            .padding(.horizontal, 6)
            .frame(minWidth: size.minWidth, minHeight: size.height, maxHeight: size.height)
            .background(line.school ? AnyShapeStyle(AC.surface) : AnyShapeStyle(color), in: shape)
            .overlay { if line.school { shape.strokeBorder(color, lineWidth: 1.5) } }
            .accessibilityLabel(line.number)
    }
}

/// The app's card: white (or raised in dark mode), rounded, with a thin border
struct AppCard<Content: View>: View {
    var padding: CGFloat = 16
    var spacing: CGFloat = 12
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(.horizontal, padding)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AC.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AC.border, lineWidth: 1))
    }
}

/// Says the timetables are sample data, not the operator's
struct PlaceholderBanner: View {
    let visible: Bool

    var body: some View {
        if visible {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                Text(L("placeholder_banner")).font(.brand(14))
            }
            .foregroundStyle(AC.bannerText)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AC.bannerBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Section heading, the same size everywhere, with an optional button on the right
struct SectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(text).font(.brand(15, .semibold)).foregroundStyle(AC.onBackground)
            Spacer()
            trailing
        }
        .padding(.leading, 4)
        .padding(.top, 10)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ text: String) {
        self.text = text
        trailing = EmptyView()
    }
}

/// A small label in the banner colours, e.g. a walking distance or "Last"
struct Pill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.brand(12, .semibold))
            .lineLimit(1)
            .foregroundStyle(AC.bannerText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AC.bannerBg, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// A star that adds the stop to the favourites or takes it out
struct FavoriteButton: View {
    let stopId: String
    var tint: Color = AC.muted
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        let on = settings.isFavorite(stopId)
        Button {
            settings.toggleFavorite(stopId)
        } label: {
            Image(systemName: on ? "star.fill" : "star")
                .foregroundStyle(on ? AC.star : tint)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L(on ? "remove_favorite" : "add_favorite"))
    }
}

/// An info icon next to a departure the operator wrote something about, e.g. "Μαθητικό"
struct NoteButton: View {
    let note: String
    var tint: Color = AC.link
    @State private var open = false

    var body: some View {
        Button {
            open = true
        } label: {
            Image(systemName: "info.circle").font(.system(size: 16)).foregroundStyle(tint).frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("note_show"))
        .alert(L("note_title"), isPresented: $open) {
            Button(L("close"), role: .cancel) {}
        } message: {
            Text(note)
        }
    }
}

/// A time, with the live mark before it when it comes from where the bus really is
private struct LiveMark<Content: View>: View {
    let live: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if live {
            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AC.live)
                    .accessibilityLabel(L("live_time"))
                content
            }
        } else {
            content
        }
    }
}

/// One departure. Within the hour the minutes are what you read first, with the clock time under them;
/// later ones show the clock time only. A bus that already left is shown faded.
struct DepartureRow: View {
    let dep: Departure
    let now: LocalDateTime
    var departed = false

    var body: some View {
        let mins = Schedule.minutesUntil(dep, now: now)
        let clock = Schedule.formatMinutes(dep.minutes)
        let within = !departed && dep.dayOffset == 0 && mins < 60
        HStack(spacing: 12) {
            LineBadge(line: dep.line)
            VStack(alignment: .leading, spacing: 1) {
                Text(dep.line.name.text).font(.brand(15, .medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(departed ? L("departed") : L("towards", dep.direction.headsign.text))
                        .font(.brand(12))
                        .foregroundStyle(AC.muted)
                        .lineLimit(1)
                    if !departed && dep.last && dep.dayOffset == 0 { Pill(text: L("last_trip")) }
                }
            }
            Spacer(minLength: 4)
            if let note = dep.note { NoteButton(note: note) }
            VStack(alignment: .trailing, spacing: 0) {
                if departed {
                    Text(clock).font(.brand(15, .medium)).foregroundStyle(AC.muted)
                } else if within {
                    LiveMark(live: dep.live) {
                        Text(mins <= 0 ? L("now") : L("minutes_only", mins))
                            .font(.brand(22, .semibold))
                            .foregroundStyle(dep.live ? AC.live : AC.onBackground)
                    }
                    Text(clock).font(.brand(12)).foregroundStyle(AC.muted)
                } else {
                    LiveMark(live: dep.live) {
                        Text(clock).font(.brand(17, .semibold)).foregroundStyle(dep.live ? AC.live : AC.onBackground)
                    }
                    if dep.dayOffset > 0 { Text(L("tomorrow")).font(.brand(12)).foregroundStyle(AC.muted) }
                }
            }
        }
        .frame(minHeight: 60)
        .opacity(departed ? 0.55 : 1)
        .contentShape(Rectangle())
    }
}

/// Hairline between rows, starting after the badge column
struct RowDivider: View {
    var inset: CGFloat = 46

    var body: some View {
        Rectangle().fill(AC.divider).frame(height: 1).padding(.leading, inset)
    }
}

/// Departures in one list; `previous` is the bus that just left, shown faded on top
struct DepartureList: View {
    let departures: [Departure]
    let now: LocalDateTime
    var previous: Departure?

    var body: some View {
        if departures.isEmpty && previous == nil {
            Text(L("no_service")).font(.brand(14)).foregroundStyle(AC.muted)
        } else {
            VStack(spacing: 0) {
                if let previous {
                    NavigationLink(value: Route.line(previous.line.id, previous.direction.id)) {
                        DepartureRow(dep: previous, now: now, departed: true)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(Array(departures.enumerated()), id: \.element.id) { index, dep in
                    if index > 0 || previous != nil { RowDivider() }
                    NavigationLink(value: Route.line(dep.line.id, dep.direction.id)) {
                        DepartureRow(dep: dep, now: now)
                    }
                    .buttonStyle(.plain)
                }
                if departures.isEmpty {
                    RowDivider()
                    Text(L("no_more_today"))
                        .font(.brand(14))
                        .foregroundStyle(AC.muted)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// A stop with its next departures and a star, as on Home
struct StopCard: View {
    let stop: Stop
    let departures: [Departure]
    let now: LocalDateTime
    var distanceMeters: Double?

    var body: some View {
        AppCard {
            HStack {
                NavigationLink(value: Route.stop(stop.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.title).font(.brand(16, .semibold)).foregroundStyle(AC.onBackground)
                        Text(subtitle).font(.brand(12)).foregroundStyle(AC.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                FavoriteButton(stopId: stop.id)
            }
            DepartureList(departures: departures, now: now)
        }
    }

    private var subtitle: String {
        let code = L("stop_code", stop.id)
        guard let distanceMeters else { return code }
        return code + " · " + Geo.formatDistance(distanceMeters, language: Strings.language)
    }
}

/// Segmented control in the app's colours
struct Segmented<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selected: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let on = option.value == selected
                Button {
                    selected = option.value
                } label: {
                    Text(option.label)
                        .font(.brand(14, on ? .semibold : .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundStyle(on ? AC.onBackground : AC.ink2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(on ? AC.segmentOn : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .shadow(color: on ? .black.opacity(0.06) : .clear, radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AC.track, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Rounded filter chip: dark when selected, outlined otherwise
struct AppChip<Label: View>: View {
    let selected: Bool
    var horizontalPadding: CGFloat = 12
    let action: () -> Void
    @ViewBuilder let label: Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) { label }
                .foregroundStyle(selected ? AC.chipOnText : AC.ink2)
                .padding(.horizontal, horizontalPadding)
                .frame(height: 36)
                .background(selected ? AC.chipOn : AC.surface, in: Capsule())
                .overlay { if !selected { Capsule().strokeBorder(AC.border, lineWidth: 1) } }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row of text chips, one selected
struct ChipRow<T: Hashable>: View {
    let options: [(value: T, label: String)]
    @Binding var selected: T

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    AppChip(selected: option.value == selected) {
                        selected = option.value
                    } label: {
                        Text(option.label).font(.brand(13, option.value == selected ? .semibold : .medium)).lineLimit(1)
                    }
                }
            }
        }
    }
}

/// The current time, refreshed every 15 seconds while the screen shows
struct Ticking<Content: View>: View {
    var interval: TimeInterval = 15
    @ViewBuilder let content: (LocalDateTime) -> Content

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            content(LocalDateTime(context.date))
        }
    }
}

/// The bus drawn on a route strip: a dark rounded square with a light outline and a bus inside
struct BusMarker: View {
    var body: some View {
        Image(systemName: "bus.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AC.surface)
            .frame(width: 26, height: 26)
            .background(AC.onBackground, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(AC.surface, lineWidth: 2))
    }
}
