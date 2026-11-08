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

    /// The network, from `transit`
    var data: TransitData { transit.data }

    /// Reads the network and builds the timetable logic and the bus estimates over it
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

/// The app: one window with the tabs, the shared container and settings, live trips every 15 seconds while it's open
@main
struct AstikaApp: App {
    @StateObject private var container = AppContainer()
    @StateObject private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase
    /// The splash has played. CI's screenshots (`-screen …`) skip it.
    @State private var splashDone = UserDefaults.standard.string(forKey: "screen") != nil

    /// Sets the navigation and tab bars in the app's font and colours
    init() {
        BarAppearance.apply()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                content
                if !splashDone {
                    AnimatedSplash { splashDone = true }
                        .transition(.identity)
                }
            }
        }
    }

    /// The tabs with everything they share
    private var content: some View {
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
