import UIKit

/// The iOS 12 build of the app: one window with the three tabs, made again when the theme or the language
/// changes so every screen is drawn in the new one.
@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate, UITabBarControllerDelegate {
    var window: UIWindow?
    private var shownTheme: ThemeMode?
    private var shownLanguage: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        buildRoot(reopenSettings: false)
        window.makeKeyAndVisible()

        let container = AppContainer.shared
        // The published timetables, for the next start
        container.transit.refresh()
        container.announcements.refresh()
        NotificationCenter.default.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.settingsChanged()
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppContainer.shared.startLiveUpdates()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        AppContainer.shared.stopLiveUpdates()
    }

    /// A new theme or language rebuilds the screens; favourites and voice don't
    private func settingsChanged() {
        let settings = AppContainer.shared.settings
        guard settings.theme != shownTheme || settings.language != shownLanguage else { return }
        // Back on Settings, where the change was made
        buildRoot(reopenSettings: true)
    }

    private func buildRoot(reopenSettings: Bool) {
        guard let window = window else { return }
        let settings = AppContainer.shared.settings
        shownTheme = settings.theme
        shownLanguage = settings.language
        Theme.resolve(settings.theme, traits: window.traitCollection)
        BarAppearance.apply()
        window.backgroundColor = AC.background

        let home = NavigationController(rootViewController: HomeViewController())
        home.tabBarItem = UITabBarItem(title: L("tab_home"), image: Icon.home.image(24), tag: 0)

        let lines = NavigationController(rootViewController: LinesViewController())
        lines.navigationBar.prefersLargeTitles = true
        lines.tabBarItem = UITabBarItem(title: L("tab_lines"), image: Icon.lines.image(24), tag: 1)

        let map = NavigationController(rootViewController: MapViewController(lineId: nil, stopId: nil))
        map.tabBarItem = UITabBarItem(title: L("tab_map"), image: Icon.map.image(24), tag: 2)

        let tabs = TabBarController()
        tabs.viewControllers = [home, lines, map]
        tabs.delegate = self
        window.rootViewController = tabs

        if reopenSettings {
            home.pushViewController(SettingsViewController(), animated: false)
        }
    }

    /// Every tap on the Map tab brings the map back to all stops, on the user. (A tap on the tab you're on
    /// already goes back to its first screen: UIKit does that.)
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        if let nav = viewController as? UINavigationController, let map = nav.viewControllers.first as? MapViewController {
            map.tabTapped()
        }
    }
}

/// The tabs, with the status bar of the screen that shows
final class TabBarController: UITabBarController {
    override var childForStatusBarStyle: UIViewController? { selectedViewController }
}
