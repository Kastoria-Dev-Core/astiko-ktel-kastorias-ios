import SwiftUI

/// A stop's next departures, filterable by line, read out loud when voice is on
struct StopScreen: View {
    let stopId: String
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var announcements: AnnouncementsStore
    @State private var lineFilter: String?
    /// This stop's speaker button; nil follows Settings
    @State private var voiceChoice: Bool?
    @State private var announcer = Announcer()
    @State private var lastSpoken = ""
    @State private var voiceMissing = false

    var body: some View {
        if let stop = container.data.stop(stopId) {
            Ticking { now in
                content(stop, now)
            }
            .background(AC.background)
            // The stop's name is at the top of the page already
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        voiceChoice = !voiceOn
                        if voiceOn && !announcer.hasVoice { voiceMissing = true }
                    } label: {
                        Image(systemName: voiceOn ? "speaker.wave.2.fill" : "speaker.slash")
                            .foregroundStyle(voiceOn ? AC.link : AC.muted)
                    }
                    .accessibilityLabel(L(voiceOn ? "voice_mute" : "voice_unmute"))
                    NavigationLink(value: Route.map(line: nil, stop: stop.id)) {
                        Image(systemName: "map")
                    }
                    .accessibilityLabel(L("show_on_map"))
                    FavoriteButton(stopId: stop.id, tint: AC.link)
                }
            }
            .alert(L("voice_missing"), isPresented: $voiceMissing) {
                Button(L("close"), role: .cancel) {}
            }
            .task { await announcements.refresh() }
            .onDisappear { announcer.stop() }
        }
    }

    private var voiceOn: Bool { voiceChoice ?? settings.voice }

    private func content(_ stop: Stop, _ now: LocalDateTime) -> some View {
        let schedule = container.schedule
        let lines = container.data.linesAtStop(stop.id)
        let departures = Array(schedule.nextDepartures(stop.id, now: now, limit: 40, live: container.liveTrips)
            .filter { lineFilter == nil || $0.line.id == lineFilter }
            .prefix(12))
        // The bus that just left by the timetable, unless it's running late and still on its way here
        let previous = schedule.previousDeparture(stop.id, now: now)
            .flatMap { p in lineFilter == nil || p.line.id == lineFilter ? p : nil }
            .flatMap { p in departures.contains { $0.live && $0.line.id == p.line.id && $0.direction.id == p.direction.id && $0.tripStart == p.tripStart } ? nil : p }
        // The feed doesn't say which lines a post is about, so the newest one still in force is shown
        let notice = announcements.announcements?.first { $0.isActive(today: now.date, now: Date()) }
        let spoken = Array(departures.prefix(3))
        let nextIsClose = spoken.first.map { $0.dayOffset == 0 && Schedule.minutesUntil($0, now: now) <= 2 } ?? false
        // Said when the stop opens or the voice is turned on, when the filter changes, when the first bus
        // leaves, and once more when the next one is two minutes away. Not every minute.
        let spokenKey = "\(voiceOn)|\(nextIsClose)|" + spoken.map { "\($0.line.id)-\($0.direction.id)-\($0.minutes)-\($0.dayOffset)" }.joined(separator: ",")

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(stop.title).font(.brand(22, .semibold))
                    Text(L("stop_code", stop.id) + " · " + L("lines_count", lines.count)).font(.brand(13)).foregroundStyle(AC.muted)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                if lines.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            AppChip(selected: lineFilter == nil, horizontalPadding: 14) { lineFilter = nil } label: {
                                Text(L("all_filter")).font(.brand(13, .semibold))
                            }
                            ForEach(lines) { line in
                                AppChip(selected: lineFilter == line.id, horizontalPadding: 10) {
                                    lineFilter = lineFilter == line.id ? nil : line.id
                                } label: {
                                    LineBadge(line: line)
                                    Text(line.name.text).font(.brand(13, .semibold)).lineLimit(1)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    PlaceholderBanner(visible: container.data.meta.placeholder)
                    if let notice {
                        NavigationLink(value: Route.announcements) {
                            NoticeRow(title: notice.title)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(alignment: .lastTextBaseline) {
                        Text(L("next_departures")).font(.brand(15, .semibold))
                        Spacer()
                        Text(schedule.serviceDay(for: now.date).label).font(.brand(12)).foregroundStyle(AC.muted)
                    }
                    .padding(.horizontal, 4)
                    AppCard {
                        DepartureList(departures: departures, now: now, previous: previous)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }
        .onChange(of: spokenKey, initial: true) { _, key in
            guard key != lastSpoken else { return }
            lastSpoken = key
            if voiceOn {
                announcer.speak(Announcer.announcement(stopName: stop.name.text, departures: spoken, now: now))
            } else {
                announcer.stop()
            }
        }
    }
}

/// An announcement still in force, shown above the departures
private struct NoticeRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.brand(14, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text(L("notice_details")).font(.brand(12))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(AC.bannerText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AC.bannerBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
