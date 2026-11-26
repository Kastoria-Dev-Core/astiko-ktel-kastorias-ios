import UIKit

extension UIColor {
    /// A colour from 0xRRGGBB
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// "#C2410C" to a colour; grey for anything that isn't one
    convenience init(hexString: String) {
        let digits = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        self.init(hex: UInt32(digits.suffix(6), radix: 16) ?? 0x888888)
    }
}

/// Light or dark, decided when the screens are built. iOS 12 has no dark mode of its own, so "system" is
/// light there (and follows the phone on iOS 13 and later).
enum Theme {
    /// The screens are drawn dark
    static var isDark = false

    /// Works out `isDark` from the setting and, on iOS 13+, the phone
    static func resolve(_ mode: ThemeMode, traits: UITraitCollection?) {
        switch mode {
        case .light: isDark = false
        case .dark: isDark = true
        case .system:
            if #available(iOS 13.0, *) {
                isDark = traits?.userInterfaceStyle == .dark
            } else {
                isDark = false
            }
        }
    }
}

/// The app's colours, the same values as the SwiftUI app's Theme.swift, each light or dark
enum AC {
    private static func pick(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor(hex: Theme.isDark ? dark : light)
    }

    static let lake = UIColor(hex: 0x0E4C6D)
    static let routeYellow = UIColor(hex: 0xF2B33D)
    static let offWhite = UIColor(hex: 0xF7F3EA)

    static var background: UIColor { pick(0xF6F4EF, 0x101315) }
    static var surface: UIColor { pick(0xFFFFFF, 0x181C1F) }
    static var surfaceVariant: UIColor { pick(0xECE7DC, 0x22272B) }
    static var onBackground: UIColor { pick(0x10212B, 0xE6E9EB) }
    static var primary: UIColor { pick(0x0E4C6D, 0x7CB6D4) }
    static var outline: UIColor { pick(0xC9D7DF, 0x3A4247) }
    static var hero: UIColor { lake }
    static var heroText: UIColor { offWhite }
    static var heroMuted: UIColor { pick(0xBFD6E1, 0xA9C4D1) }
    static var link: UIColor { pick(0x0E4C6D, 0x7CB6D4) }
    static var bannerBg: UIColor { pick(0xFCEFD2, 0x2A2416) }
    static var bannerText: UIColor { pick(0x5A3D00, 0xE8C57A) }
    static var star: UIColor { pick(0xC88A12, 0xF2B33D) }
    static var muted: UIColor { pick(0x5F6D76, 0x8E979D) }
    static var border: UIColor { pick(0xE4DFD3, 0x2A3034) }
    static var ink2: UIColor { pick(0x4D5C66, 0xB3BBC0) }
    static var divider: UIColor { pick(0xEEEAE0, 0x23282B) }
    static var track: UIColor { pick(0xECE7DC, 0x181C1F) }
    static var live: UIColor { pick(0x0E5F86, 0x7CB6D4) }
    static var chipOn: UIColor { pick(0x10212B, 0xE6E9EB) }
    static var chipOnText: UIColor { pick(0xFFFFFF, 0x101315) }
    static var segmentOn: UIColor { pick(0xFFFFFF, 0x353C41) }
}

/// The weights of Commissioner bundled with the app
enum FontWeight {
    case regular, medium, semibold, bold
}

extension UIFont {
    /// Commissioner, the app's font, in one of its four weights
    static func brand(_ size: CGFloat, _ weight: FontWeight = .regular) -> UIFont {
        let name: String
        switch weight {
        case .bold: name = "CommissionerThin-Bold"
        case .semibold: name = "CommissionerThin-SemiBold"
        case .medium: name = "CommissionerThin-Medium"
        case .regular: name = "CommissionerThin-Regular"
        }
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
    }
}

/// The navigation and tab bars in the app's font and colours, set before the screens are made
enum BarAppearance {
    static func apply() {
        let nav = UINavigationBar.appearance()
        nav.isTranslucent = false
        nav.barTintColor = AC.background
        nav.tintColor = AC.link
        nav.shadowImage = UIImage()
        nav.setBackgroundImage(UIImage(), for: .default)
        nav.backgroundColor = AC.background
        nav.titleTextAttributes = [.font: UIFont.brand(17, .semibold), .foregroundColor: AC.onBackground]
        nav.largeTitleTextAttributes = [.font: UIFont.brand(32, .semibold), .foregroundColor: AC.onBackground]

        let tab = UITabBar.appearance()
        tab.isTranslucent = false
        tab.barTintColor = AC.surface
        tab.tintColor = AC.primary
        tab.unselectedItemTintColor = AC.ink2
        let item = UITabBarItem.appearance()
        item.setTitleTextAttributes([.font: UIFont.brand(11), .foregroundColor: AC.ink2], for: .normal)
        item.setTitleTextAttributes([.font: UIFont.brand(11, .semibold), .foregroundColor: AC.primary], for: .selected)
    }
}

/// The icons, drawn in code: iOS 12 has no SF Symbols. Each is a template image on a 24 point square, so it
/// takes the tint of the view it's in.
enum Icon {
    case home, lines, map, gear, search, clear, close, star, starFill, info, chevronRight, chevronDown, chevronUp
    case location, speakerOn, speakerOff, bus, walk, refresh, warning, pin, list, live

    private static var cache: [String: UIImage] = [:]

    /// The icon at `size` points
    func image(_ size: CGFloat = 24) -> UIImage {
        let key = "\(self)-\(size)"
        if let hit = Icon.cache[key] { return hit }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.scaleBy(x: size / 24, y: size / 24)
            UIColor.black.setStroke()
            UIColor.black.setFill()
            draw(cg)
        }.withRenderingMode(.alwaysTemplate)
        Icon.cache[key] = image
        return image
    }

    private func stroke(_ path: UIBezierPath, _ width: CGFloat = 2) {
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func line(_ points: [(CGFloat, CGFloat)], width: CGFloat = 2, close: Bool = false) -> UIBezierPath {
        let p = UIBezierPath()
        for (i, pt) in points.enumerated() {
            if i == 0 { p.move(to: CGPoint(x: pt.0, y: pt.1)) } else { p.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
        }
        if close { p.close() }
        p.lineWidth = width
        return p
    }

    private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private func starPath() -> UIBezierPath {
        let p = UIBezierPath()
        for i in 0..<10 {
            let r: CGFloat = i % 2 == 0 ? 10 : 4.3
            let a = -CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / 5
            let pt = CGPoint(x: 12 + r * cos(a), y: 12.8 + r * sin(a))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.close()
        return p
    }

    private func speakerBody() {
        line([(3, 9), (7, 9), (12, 5), (12, 19), (7, 15), (3, 15)], close: true).fill()
    }

    private func draw(_ cg: CGContext) {
        switch self {
        case .home:
            stroke(line([(3.5, 11.5), (12, 4), (20.5, 11.5)]))
            stroke(line([(6, 10), (6, 20), (18, 20), (18, 10)]))
            stroke(line([(10, 20), (10, 14.5), (14, 14.5), (14, 20)]))
        case .lines:
            stroke(circle(6, 18, 2.6))
            stroke(circle(18, 6, 2.6))
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 8.6, y: 18))
            p.addCurve(to: CGPoint(x: 15.4, y: 6), controlPoint1: CGPoint(x: 18, y: 18), controlPoint2: CGPoint(x: 6, y: 6))
            stroke(p)
        case .map:
            stroke(line([(3, 6.5), (9, 4), (15, 6.5), (21, 4), (21, 17.5), (15, 20), (9, 17.5), (3, 20)], close: true))
            stroke(line([(9, 4), (9, 17.5)]))
            stroke(line([(15, 6.5), (15, 20)]))
        case .gear:
            stroke(circle(12, 12, 3))
            stroke(circle(12, 12, 6.8))
            for i in 0..<8 {
                let a = CGFloat(i) * CGFloat.pi / 4
                stroke(line([(12 + 6.8 * cos(a), 12 + 6.8 * sin(a)), (12 + 9.6 * cos(a), 12 + 9.6 * sin(a))]), 2.6)
            }
        case .search:
            stroke(circle(10.5, 10.5, 6.2))
            stroke(line([(15.2, 15.2), (20.5, 20.5)]), 2.4)
        case .clear:
            circle(12, 12, 9.5).fill()
            cg.setBlendMode(.clear)
            stroke(line([(8.5, 8.5), (15.5, 15.5)]))
            stroke(line([(15.5, 8.5), (8.5, 15.5)]))
            cg.setBlendMode(.normal)
        case .close:
            stroke(line([(6, 6), (18, 18)]), 2.3)
            stroke(line([(18, 6), (6, 18)]), 2.3)
        case .star:
            stroke(starPath(), 1.8)
        case .starFill:
            starPath().fill()
        case .info:
            stroke(circle(12, 12, 9), 1.8)
            circle(12, 7.6, 1.3).fill()
            stroke(line([(12, 11), (12, 17)]), 2.2)
        case .chevronRight:
            stroke(line([(9, 5), (16, 12), (9, 19)]), 2.4)
        case .chevronDown:
            stroke(line([(5, 9), (12, 16), (19, 9)]), 2.4)
        case .chevronUp:
            stroke(line([(5, 15), (12, 8), (19, 15)]), 2.4)
        case .location:
            let p = line([(20.5, 3.5), (3.5, 11), (11, 13), (13, 20.5)], close: true)
            p.lineJoinStyle = .round
            p.fill()
        case .speakerOn:
            speakerBody()
            for r in [CGFloat(4), 7.5] {
                let arc = UIBezierPath(arcCenter: CGPoint(x: 12.5, y: 12), radius: r, startAngle: -0.75, endAngle: 0.75, clockwise: true)
                stroke(arc)
            }
        case .speakerOff:
            speakerBody()
            stroke(line([(15.5, 9), (21, 14.5)]))
            stroke(line([(21, 9), (15.5, 14.5)]))
        case .bus:
            UIBezierPath(roundedRect: CGRect(x: 5, y: 3, width: 14, height: 15.5), cornerRadius: 3.2).fill()
            circle(8.2, 19.6, 1.8).fill()
            circle(15.8, 19.6, 1.8).fill()
            cg.setBlendMode(.clear)
            UIBezierPath(roundedRect: CGRect(x: 7, y: 5.5, width: 10, height: 5.5), cornerRadius: 1.2).fill()
            circle(8.3, 14.8, 1.2).fill()
            circle(15.7, 14.8, 1.2).fill()
            cg.setBlendMode(.normal)
        case .walk:
            circle(13.5, 4, 2.1).fill()
            stroke(line([(12.5, 8), (11, 14)]), 2.4)
            stroke(line([(11, 14), (8, 20.5)]), 2.2)
            stroke(line([(11, 14), (14, 16.5), (15, 20.5)]), 2.2)
            stroke(line([(12.3, 9), (8.5, 11.5)]), 2)
            stroke(line([(12.3, 9), (15.5, 12)]), 2)
        case .refresh:
            let arc = UIBezierPath(arcCenter: CGPoint(x: 12, y: 12.5), radius: 7.5, startAngle: -CGFloat.pi / 2 + 0.5,
                                   endAngle: -CGFloat.pi / 2 - 0.3 + 2 * CGFloat.pi, clockwise: true)
            stroke(arc)
            line([(10.5, 1.8), (15.5, 5.2), (10.5, 8.4)], close: true).fill()
        case .warning:
            stroke(line([(12, 3.5), (21.5, 20), (2.5, 20)], close: true), 1.9)
            stroke(line([(12, 9.5), (12, 14)]), 2.2)
            circle(12, 17, 1.2).fill()
        case .pin:
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 12, y: 21.5))
            p.addCurve(to: CGPoint(x: 5.5, y: 9.5), controlPoint1: CGPoint(x: 9, y: 17.5), controlPoint2: CGPoint(x: 5.5, y: 13.5))
            p.addArc(withCenter: CGPoint(x: 12, y: 9.5), radius: 6.5, startAngle: CGFloat.pi, endAngle: 0, clockwise: true)
            p.addCurve(to: CGPoint(x: 12, y: 21.5), controlPoint1: CGPoint(x: 18.5, y: 13.5), controlPoint2: CGPoint(x: 15, y: 17.5))
            stroke(p, 1.9)
            circle(12, 9.5, 2.3).fill()
        case .list:
            for y in [CGFloat(6), 12, 18] {
                circle(5, y, 1.5).fill()
                stroke(line([(9, y), (20, y)]))
            }
        case .live:
            circle(12, 12, 1.9).fill()
            for r in [CGFloat(5), 8.5] {
                stroke(UIBezierPath(arcCenter: CGPoint(x: 12, y: 12), radius: r, startAngle: -0.65, endAngle: 0.65, clockwise: true))
                stroke(UIBezierPath(arcCenter: CGPoint(x: 12, y: 12), radius: r, startAngle: CGFloat.pi - 0.65, endAngle: CGFloat.pi + 0.65, clockwise: true))
            }
        }
    }
}
