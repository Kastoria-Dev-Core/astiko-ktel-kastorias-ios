import SwiftUI

extension Destination {
    var label: String {
        switch self {
        case .centre: return L("destination_centre")
        case .maniakoi: return L("destination_maniakoi")
        case .university: return L("destination_university")
        }
    }
}

/// "Where do you want to go?" on Home: pick a place and see every bus that goes there from a stop near you,
/// the one that comes first at the top
struct JourneySection: View {
    @Binding var destination: Destination?
    let nearby: NearbyState
    let now: LocalDateTime
    let onLocate: () -> Void
    @EnvironmentObject private var container: AppContainer
    /// Only the 3 soonest buses, until "All buses"
    @State private var showAll = false

    private let collapsed = 3

    var body: some View {
        AppCard(padding: 14, spacing: 0) {
            ZStack {
                VStack(spacing: 1) {
                    Text(L("journey_title")).font(.brand(16, .semibold))
                    Text(L("journey_subtitle")).font(.brand(13)).foregroundStyle(AC.muted)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
                if destination != nil {
                    HStack {
                        Spacer()
                        Button(action: onLocate) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(nearby == .loading ? AC.muted : AC.link)
                                .frame(width: 44, height: 44)
                        }
                        .disabled(nearby == .loading)
                        .accessibilityLabel(L("journey_refresh_location"))
                    }
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                ForEach(Destination.allCases) { d in
                    let on = d == destination
                    Button {
                        // Tapping the selected destination again clears it
                        destination = on ? nil : d
                        showAll = false
                        if destination != nil && nearby == .idle { onLocate() }
                    } label: {
                        Text(d.label)
                            .font(.brand(14, on ? .semibold : .medium))
                            .lineLimit(1)
                            .foregroundStyle(on ? AC.chipOnText : AC.ink2)
                            .padding(.horizontal, 14)
                            .frame(height: 40)
                            .background(on ? AC.chipOn : AC.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(on ? AC.chipOn : AC.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)

            if let destination {
                planView(for: destination)
            }
        }
    }

    @ViewBuilder
    private func planView(for destination: Destination) -> some View {
        if let coords = nearby.coords,
           let plan = JourneyPlanner.plan(data: container.data, schedule: container.schedule, destination: destination,
                                          lat: coords.lat, lng: coords.lng, now: now) {
            VStack(alignment: .leading, spacing: 0) {
                if plan.status != .alreadyThere && plan.status != .tooFar {
                    let stop = plan.usefulStop ?? plan.nearestStop
                    StopToWalkTo(stop: stop, label: L(plan.usefulStop != nil ? "journey_useful_stop" : "journey_nearest_stop"))
                    if plan.usefulStop != nil {
                        Text(L("journey_nearest_no_bus", plan.nearestStop.stop.name.text,
                               Geo.formatDistance(plan.nearestStop.distanceMeters, language: Strings.language)))
                            .font(.brand(13))
                            .foregroundStyle(AC.muted)
                            .padding(.leading, 4)
                            .padding(.top, 2)
                    }
                }
                switch plan.status {
                case .tooFar: JourneyMessage(text: L("journey_too_far"))
                case .alreadyThere: JourneyMessage(text: L("journey_already_there", plan.nearestStop.stop.name.text))
                case .noRoute: JourneyMessage(text: L("journey_no_route"))
                case .noMoreBuses: JourneyMessage(text: L("journey_no_more_buses"))
                case .ready: options(plan)
                }
            }
        } else {
            let loading = nearby == .loading
            JourneyMessage(text: L(message), action: loading ? nil : L("find_nearby"), onAction: onLocate)
        }
    }

    private var message: String {
        switch nearby {
        case .loading: return "locating"
        case .denied: return "location_denied"
        case .disabled: return "location_unsupported"
        case .error: return "location_error"
        default: return "journey_need_location"
        }
    }

    @ViewBuilder
    private func options(_ plan: JourneyPlan) -> some View {
        let shown = showAll ? plan.options : Array(plan.options.prefix(collapsed))
        VStack(spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, option in
                NavigationLink(value: Route.stop(option.ride.board.stop.id)) {
                    JourneyOptionRow(option: option,
                                     alightName: container.data.stop(option.ride.alightStopId)?.name.text ?? option.ride.alightStopId,
                                     highlighted: index == 0)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        if plan.options.count > collapsed {
            Button {
                showAll.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(showAll ? L("journey_show_less") : L("journey_show_all", plan.options.count)).font(.brand(15, .semibold))
                    Image(systemName: showAll ? "chevron.up" : "chevron.down")
                }
                .foregroundStyle(AC.link)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        Text(L("journey_note"))
            .font(.brand(12))
            .foregroundStyle(AC.muted)
            .padding(.leading, 4)
            .padding(.top, plan.options.count > collapsed ? 0 : 8)
    }
}

/// The stop to walk to: its name and distance. Tap to open the stop.
private struct StopToWalkTo: View {
    let stop: NearbyStop
    let label: String

    var body: some View {
        NavigationLink(value: Route.stop(stop.stop.id)) {
            HStack(spacing: 10) {
                Image(systemName: "figure.walk")
                    .foregroundStyle(AC.link)
                    .frame(width: 34, height: 34)
                    .background(AC.surfaceVariant, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.brand(12)).foregroundStyle(AC.muted)
                    Text(stop.stop.title).font(.brand(15, .semibold)).lineLimit(1)
                }
                Spacer()
                Pill(text: Geo.formatDistance(stop.distanceMeters, language: Strings.language))
            }
            .frame(minHeight: 48)
            .padding(.top, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A tinted box with a short message and, optionally, a button
private struct JourneyMessage: View {
    let text: String
    var action: String?
    var onAction: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.fill").foregroundStyle(AC.link)
            Text(text).font(.brand(14)).padding(.vertical, 8)
            Spacer(minLength: 0)
            if let action {
                Button(action, action: onAction).font(.brand(15, .bold)).foregroundStyle(AC.link)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(AC.surfaceVariant, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 10)
    }
}

/// One bus that takes you there. The first (soonest) one is filled.
private struct JourneyOptionRow: View {
    let option: JourneyOption
    let alightName: String
    let highlighted: Bool

    var body: some View {
        let strong = highlighted ? AC.heroText : AC.onBackground
        let soft = highlighted ? AC.heroMuted : AC.muted
        let number = highlighted ? AC.heroText : AC.link
        let board = option.ride.board
        HStack(spacing: 10) {
            LineBadge(line: option.ride.line, size: .md)
            VStack(alignment: .leading, spacing: 1) {
                if highlighted { Text(L("journey_fastest")).font(.brand(12, .semibold)).foregroundStyle(soft) }
                Text(option.ride.line.name.text).font(.brand(15, .bold)).foregroundStyle(strong).lineLimit(1)
                HStack(spacing: 4) {
                    Text(L("journey_board", board.stop.title)).lineLimit(1)
                    Image(systemName: "figure.walk").font(.system(size: 11))
                    Text(L("journey_walk_minutes", board.walkMinutes)).lineLimit(1).fixedSize()
                }
                .font(.brand(13))
                .foregroundStyle(soft)
                Text(L("journey_alight", alightName)).font(.brand(13)).foregroundStyle(soft).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(spacing: 0) {
                if option.minutesUntil == 0 {
                    Text(L("now")).font(.brand(20, .bold)).foregroundStyle(strong)
                } else if option.minutesUntil > 59 {
                    // "368 min" is hard to read: an hour or more away we write "6h 8′"
                    let hours = option.minutesUntil / 60
                    let minutes = option.minutesUntil % 60
                    Text(minutes == 0 ? L("duration_hours", hours) : L("duration_hours_minutes", hours, minutes))
                        .font(.brand(highlighted ? 22 : 18, .bold))
                        .foregroundStyle(number)
                } else {
                    Text("\(option.minutesUntil)").font(.brand(highlighted ? 28 : 22, .bold)).foregroundStyle(number)
                    Text(L("minutes_short")).font(.brand(11)).foregroundStyle(soft)
                }
                Text(Schedule.formatMinutes(option.minutes)).font(.brand(12, .semibold)).foregroundStyle(strong)
                if let later = option.later {
                    Text(L("journey_later", Schedule.formatMinutes(later))).font(.brand(11)).foregroundStyle(soft)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(highlighted ? AC.hero : AC.surfaceVariant, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
