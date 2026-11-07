import SwiftUI

/// Everything the screens share, made once: the network, its timetable logic and the services
@MainActor
final class AppContainer: ObservableObject {
    /// Lines, stops and timetables: the latest published copy, or the app's own
    let transit: TransitRepository
    /// The timetable logic over `transit`
    let schedule: Schedule
    /// Where the buses are along their routes, estimated from `schedule`
    let busEstimator: BusEstimator
    /// Where the buses really are, for the ones whose phone is sending
    let liveBuses = LiveBusesRepository()
    /// The phone's position, for stops nearby and the map
    let location = LocationClient()
    /// The operator's announcements
    let announcements = AnnouncementsStore()

    /// The trips whose bus is sending where it is, with how late each runs. Updated every 15 seconds
    /// while the app is open.
    @Published private(set) var liveTrips: [LiveTrip] = []

    var data: TransitData { transit.data }

    init() {
        transit = TransitRepository()
        schedule = Schedule(transit.data)
        busEstimator = BusEstimator(data: transit.data, schedule: schedule)
    }

    /// Asks for the live buses and works out their trips, once
    func refreshLiveTrips() async {
        let buses = await liveBuses.buses()
        liveTrips = LiveTrips.compute(data: data, schedule: schedule, buses: buses)
    }
}

@main
struct AstikaApp: App {
    @StateObject private var container = AppContainer()
    @StateObject private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BarAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // A new language rebuilds every screen, so all text is read again
                .id(settings.language)
                .environmentObject(container)
                .environmentObject(settings)
                .environmentObject(container.announcements)
                .font(.brand(15))
                .tint(AC.primary)
                .preferredColorScheme(settings.theme == .light ? .light : settings.theme == .dark ? .dark : nil)
                .task {
                    // The published timetables, for the next start
                    await container.transit.refresh()
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await container.refreshLiveTrips()
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                    }
                }
        }
    }
}
