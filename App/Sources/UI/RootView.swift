import SwiftUI

/// Every screen the app can open on top of a tab
enum Route: Hashable {
    /// A stop's next departures
    case stop(String)
    /// A line's timetable, in this direction or the first
    case line(String, String?)
    /// Every stop of a direction with when the next bus gets there
    case routeStops(String, String)
    /// The map on a line or a stop, opened from another screen
    case map(line: String?, stop: String?)
    case announcements
    case settings
    case about
}

/// The bottom tabs
enum Tab: Hashable {
    case home, lines, map
}

/// The bottom tabs. Each has its own navigation stack, so a screen opened from a tab stays part of it, and
/// tapping the tab you're on goes back to its first screen. Each tap on Map also brings the map back to
/// where you are.
struct RootView: View {
    @State private var tab: Tab = .home
    @State private var homePath: [Route] = []
    @State private var linesPath: [Route] = []
    @State private var mapPath: [Route] = []
    /// Counts taps on the Map tab, so the map knows to go back to the user
    @State private var mapRecenter = 0
    @State private var openedFromArguments = false

    var body: some View {
        TabView(selection: tabSelection) {
            NavigationStack(path: $homePath) {
                HomeScreen().routes()
            }
            .tabItem { Label(L("tab_home"), systemImage: "house") }
            .tag(Tab.home)

            NavigationStack(path: $linesPath) {
                LinesScreen().routes()
            }
            .tabItem { Label(L("tab_lines"), systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            .tag(Tab.lines)

            NavigationStack(path: $mapPath) {
                MapScreen(initialLineId: nil, initialStopId: nil, recenter: mapRecenter).routes()
            }
            .tabItem { Label(L("tab_map"), systemImage: "map") }
            .tag(Tab.map)
        }
        .onAppear(perform: openFromArguments)
    }

    /// A tap on the tab you're on goes back to its first screen; every tap on Map recentres the map
    private var tabSelection: Binding<Tab> {
        Binding(
            get: { tab },
            set: { picked in
                if picked == .map { mapRecenter += 1 }
                if picked == tab {
                    switch picked {
                    case .home: homePath = []
                    case .lines: linesPath = []
                    case .map: mapPath = []
                    }
                }
                tab = picked
            }
        )
    }

    /// `-screen stop:16001` and the like open the app straight on a screen, for the CI screenshots
    private func openFromArguments() {
        guard !openedFromArguments, let screen = UserDefaults.standard.string(forKey: "screen") else { return }
        openedFromArguments = true
        let parts = screen.split(separator: ":", maxSplits: 1).map(String.init)
        let arg = parts.count > 1 ? parts[1] : nil
        switch parts[0] {
        case "lines": tab = .lines
        case "map": tab = .map
        case "line": if let arg { homePath = [.line(arg, nil)] }
        case "route": if let arg { homePath = [.routeStops(arg, "out")] }
        case "stop": if let arg { homePath = [.stop(arg)] }
        case "mapline": if let arg { homePath = [.map(line: arg, stop: nil)] }
        case "announcements": homePath = [.announcements]
        case "settings": homePath = [.settings]
        default: break
        }
    }
}

extension View {
    /// The screens every tab can open
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .stop(let id): StopScreen(stopId: id)
            case .line(let id, let direction): LineScreen(lineId: id, initialDirectionId: direction)
            case .routeStops(let id, let direction): RouteStopsScreen(lineId: id, initialDirectionId: direction)
            case .map(let line, let stop): MapScreen(initialLineId: line, initialStopId: stop, recenter: 0)
            case .announcements: AnnouncementsScreen()
            case .settings: SettingsScreen()
            case .about: AboutScreen()
            }
        }
    }
}
