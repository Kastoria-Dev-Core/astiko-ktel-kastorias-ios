import SwiftUI
import UIKit

extension UIColor {
    /// A colour from 0xRRGGBB
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// One colour in light mode and another in dark mode
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }

    /// "#C2410C" to a colour; grey for anything that isn't one
    init(hexString: String) {
        let digits = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(digits.suffix(6), radix: 16) ?? 0x888888
        self.init(uiColor: UIColor(hex: value))
    }
}

/// The app's colours, taken from the app icon (the route by the lake), the same as the Android app's
/// Theme.kt. Each has a light and a dark value.
enum AC {
    // The icon's colours
    static let lake = Color(uiColor: UIColor(hex: 0x0E4C6D))
    static let routeYellow = Color(uiColor: UIColor(hex: 0xF2B33D))
    static let offWhite = Color(uiColor: UIColor(hex: 0xF7F3EA))

    // Surfaces and text
    static let background = Color.adaptive(0xF6F4EF, 0x101315)
    static let surface = Color.adaptive(0xFFFFFF, 0x181C1F)
    static let surfaceVariant = Color.adaptive(0xECE7DC, 0x22272B)
    static let onBackground = Color.adaptive(0x10212B, 0xE6E9EB)
    static let primary = Color.adaptive(0x0E4C6D, 0x7CB6D4)
    static let outline = Color.adaptive(0xC9D7DF, 0x3A4247)

    // What Material has no slot for
    static let hero = lake
    static let heroText = offWhite
    static let heroMuted = Color.adaptive(0xBFD6E1, 0xA9C4D1)
    static let link = Color.adaptive(0x0E4C6D, 0x7CB6D4)
    static let bannerBg = Color.adaptive(0xFCEFD2, 0x2A2416)
    static let bannerBorder = Color.adaptive(0xF1DDAE, 0x453A1E)
    static let bannerText = Color.adaptive(0x5A3D00, 0xE8C57A)
    static let star = Color.adaptive(0xC88A12, 0xF2B33D)
    static let muted = Color.adaptive(0x5F6D76, 0x8E979D)
    static let border = Color.adaptive(0xE4DFD3, 0x2A3034)
    static let ink2 = Color.adaptive(0x4D5C66, 0xB3BBC0)
    static let divider = Color.adaptive(0xEEEAE0, 0x23282B)
    static let track = Color.adaptive(0xECE7DC, 0x181C1F)
    static let activeBg = Color.adaptive(0xE1ECF1, 0x1F2C33)
    static let live = Color.adaptive(0x0E5F86, 0x7CB6D4)
    static let highlight = Color.adaptive(0xFBF6EA, 0x1C2328)
    static let chipOn = Color.adaptive(0x10212B, 0xE6E9EB)
    static let chipOnText = Color.adaptive(0xFFFFFF, 0x101315)
    static let segmentOn = Color.adaptive(0xFFFFFF, 0x353C41)
}

extension Font {
    /// Commissioner, the Android app's font (OFL), bundled in four weights
    static func brand(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "CommissionerThin-Bold"
        case .semibold: name = "CommissionerThin-SemiBold"
        case .medium: name = "CommissionerThin-Medium"
        default: name = "CommissionerThin-Regular"
        }
        return .custom(name, size: size)
    }
}

extension UIFont {
    static func brand(_ size: CGFloat, semibold: Bool = false) -> UIFont {
        UIFont(name: semibold ? "CommissionerThin-SemiBold" : "CommissionerThin-Regular", size: size) ?? .systemFont(ofSize: size)
    }
}

/// The navigation and tab bars in the app's font and colours
enum BarAppearance {
    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(AC.background)
        nav.shadowColor = .clear
        nav.titleTextAttributes = [.font: UIFont.brand(17, semibold: true), .foregroundColor: UIColor(AC.onBackground)]
        nav.largeTitleTextAttributes = [.font: UIFont.brand(32, semibold: true), .foregroundColor: UIColor(AC.onBackground)]
        let buttons = UIBarButtonItemAppearance()
        buttons.normal.titleTextAttributes = [.font: UIFont.brand(17)]
        nav.buttonAppearance = buttons
        nav.backButtonAppearance = buttons
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(AC.surface)
        tab.shadowColor = UIColor(AC.border)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.titleTextAttributes = [.font: UIFont.brand(11), .foregroundColor: UIColor(AC.ink2)]
            item.selected.titleTextAttributes = [.font: UIFont.brand(11, semibold: true), .foregroundColor: UIColor(AC.primary)]
            item.normal.iconColor = UIColor(AC.ink2)
            item.selected.iconColor = UIColor(AC.primary)
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}
