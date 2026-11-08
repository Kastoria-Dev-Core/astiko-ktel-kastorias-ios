import SwiftUI

/// A timing curve like CSS's cubic-bezier(x1, y1, x2, y2), the same easings the Android splash uses
struct CubicBezier {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double

    /// Progress along the curve for a linear progress `t` from 0 to 1
    func callAsFunction(_ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        // Solve x(u) = t with Newton's method, then read y at u
        var u = t
        for _ in 0..<8 {
            let x = curve(u, x1, x2) - t
            let dx = slope(u, x1, x2)
            if abs(x) < 1e-6 || abs(dx) < 1e-6 { break }
            u -= x / dx
        }
        return curve(min(max(u, 0), 1), y1, y2)
    }

    private func curve(_ u: Double, _ a: Double, _ b: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
    }

    private func slope(_ u: Double, _ a: Double, _ b: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
    }
}

/// The animated splash, built from the app icon, the same as the Android app's AnimatedSplash.kt.
///
/// Design space: 390 x 844 units. The art sits at 39% of the height and the waves stick to the bottom
/// edge. Timings in ms: 0-430 the waves rise, 290-1220 the route draws, the stops pop at 320 and 720, the
/// bus at 1120, the title at 1370, the loader from 1550, then a 360 ms exit that reveals Home underneath.
/// The network is read before the first frame on iOS, so the splash never waits for it.
struct AnimatedSplash: View {
    /// Called once the exit has played, to take the splash away
    let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let introMs = 1800.0
    private static let exitMs = 360.0
    private static let easeOut = CubicBezier(x1: 0.2, y1: 0.8, x2: 0.2, y2: 1)
    private static let routeEasing = CubicBezier(x1: 0.65, y1: 0, x2: 0.35, y2: 1)
    private static let overshoot = CubicBezier(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1)
    private static let exitEasing = CubicBezier(x1: 0.4, y1: 0, x2: 0.2, y2: 1)

    private static let lake = Color(uiColor: UIColor(hex: 0x0E4C6D))
    private static let lakeMid = Color(uiColor: UIColor(hex: 0x16627F))
    private static let lakeLight = Color(uiColor: UIColor(hex: 0x1B7394))
    private static let yellow = Color(uiColor: UIColor(hex: 0xF2B33D))
    private static let offWhite = Color(uiColor: UIColor(hex: 0xF7F3EA))
    private static let titleBlue = Color(uiColor: UIColor(hex: 0xBFD6E1))

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start) * 1000
            let t = reduceMotion ? AnimatedSplash.introMs : min(elapsed, AnimatedSplash.introMs + AnimatedSplash.exitMs)
            let exit = reduceMotion ? 0 : AnimatedSplash.exitEasing((elapsed - AnimatedSplash.introMs) / AnimatedSplash.exitMs)
            GeometryReader { geo in
                let unit = geo.size.width / 390
                ZStack(alignment: .top) {
                    Canvas { ctx, size in
                        AnimatedSplash.draw(&ctx, size: size, t: t)
                    }
                    title(t: t, elapsed: elapsed, unit: unit)
                        .offset(y: geo.size.height * 0.39 + unit * 150)
                }
                .scaleEffect(1 + 0.06 * exit, anchor: UnitPoint(x: 0.5, y: 0.39))
            }
            .background(AnimatedSplash.lake)
            .opacity(1 - exit)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        // Nothing underneath reacts to taps while the splash is up
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityHidden(true)
        .task {
            let ms = reduceMotion ? 500.0 : AnimatedSplash.introMs + AnimatedSplash.exitMs
            try? await Task.sleep(nanoseconds: UInt64(ms * 1_000_000))
            onFinished()
        }
    }

    // MARK: - The title and the loader

    private func title(t: Double, elapsed: Double, unit: CGFloat) -> some View {
        let titleIn = AnimatedSplash.window(t, 1368, 1800, AnimatedSplash.easeOut)
        let loaderIn = min(max((t - 1550) / 250, 0), 1)
        // The bar slides across the track every 640 ms
        let bar = reduceMotion ? 0 : -56 + 112 * (elapsed.truncatingRemainder(dividingBy: 640) / 640)
        return VStack(spacing: 0) {
            Text(L("splash_title_1"))
                .font(.brand(30 * unit, .bold))
                .foregroundStyle(AnimatedSplash.offWhite)
            Text(L("splash_title_2"))
                .font(.brand(20 * unit, .medium))
                .foregroundStyle(AnimatedSplash.titleBlue)
            ZStack(alignment: .leading) {
                Capsule().fill(AnimatedSplash.offWhite.opacity(0.18))
                Capsule()
                    .fill(AnimatedSplash.yellow)
                    .frame(width: 40 * unit)
                    .offset(x: unit * (20 + bar))
            }
            .frame(width: 80 * unit, height: 4 * unit)
            .clipShape(Capsule())
            .opacity(loaderIn)
            .padding(.top, 22 * unit)
        }
        .frame(maxWidth: .infinity)
        .opacity(titleIn)
        .offset(y: (1 - titleIn) * 18 * unit)
    }

    // MARK: - Drawing

    /// Progress 0...1 of `t` inside `start...end`, eased
    private static func window(_ t: Double, _ start: Double, _ end: Double, _ easing: CubicBezier) -> Double {
        easing(min(max((t - start) / (end - start), 0), 1))
    }

    /// A stop popping in: 0, up to 1.25, back to 1
    private static func pop(_ t: Double, _ start: Double) -> Double {
        if t <= start { return 0 }
        if t < start + 180 { return 1.25 * easeOut((t - start) / 180) }
        if t < start + 288 { return 1.25 - 0.25 * ((t - start - 180) / 108) }
        return 1
    }

    /// A small double hop of the bus after it lands, in icon units
    private static func hop(_ t: Double) -> Double {
        func lerp(_ a: Double, _ b: Double, _ f: Double) -> Double { a + (b - a) * min(max(f, 0), 1) }
        if t < 1440 { return 0 }
        if t < 1548 { return lerp(0, -8, (t - 1440) / 108) }
        if t < 1656 { return lerp(-8, 0, (t - 1548) / 108) }
        if t < 1728 { return lerp(0, -3, (t - 1656) / 72) }
        if t < 1800 { return lerp(-3, 0, (t - 1728) / 72) }
        return 0
    }

    private static let wave1 = Path { p in
        p.move(to: CGPoint(x: 0, y: 690))
        p.addCurve(to: CGPoint(x: 290, y: 645), control1: CGPoint(x: 90, y: 650), control2: CGPoint(x: 190, y: 690))
        p.addCurve(to: CGPoint(x: 390, y: 606), control1: CGPoint(x: 330, y: 628), control2: CGPoint(x: 365, y: 612))
        p.addLine(to: CGPoint(x: 390, y: 844))
        p.addLine(to: CGPoint(x: 0, y: 844))
        p.closeSubpath()
    }

    private static let wave2 = Path { p in
        p.move(to: CGPoint(x: 0, y: 770))
        p.addCurve(to: CGPoint(x: 390, y: 716), control1: CGPoint(x: 110, y: 738), control2: CGPoint(x: 230, y: 772))
        p.addLine(to: CGPoint(x: 390, y: 844))
        p.addLine(to: CGPoint(x: 0, y: 844))
        p.closeSubpath()
    }

    /// The route in icon units (512 space): M150 360 C150 300, 250 330, 250 270 S340 240, 340 180
    private static let route = Path { p in
        p.move(to: CGPoint(x: 150, y: 360))
        p.addCurve(to: CGPoint(x: 250, y: 270), control1: CGPoint(x: 150, y: 300), control2: CGPoint(x: 250, y: 330))
        p.addCurve(to: CGPoint(x: 340, y: 180), control1: CGPoint(x: 250, y: 210), control2: CGPoint(x: 340, y: 240))
    }

    private static func draw(_ ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let s = size.width / 390
        let bottom = size.height - 844 * s
        let w1 = window(t, 0, 432, easeOut)
        if w1 > 0 {
            var c = ctx
            c.translateBy(x: 0, y: bottom + (1 - w1) * 90 * s)
            c.scaleBy(x: s, y: s)
            c.opacity = w1
            c.fill(wave1, with: .color(lakeMid))
        }
        let w2 = window(t, 144, 576, easeOut)
        if w2 > 0 {
            var c = ctx
            c.translateBy(x: 0, y: bottom + (1 - w2) * 120 * s)
            c.scaleBy(x: s, y: s)
            c.opacity = w2
            c.fill(wave2, with: .color(lakeLight))
        }
        var art = ctx
        art.translateBy(x: size.width / 2 - 195 * s, y: size.height * 0.39 - 330 * s)
        art.scaleBy(x: s, y: s)
        art.translateBy(x: -3.75, y: 142.5)
        art.scaleBy(x: 0.75, y: 0.75)
        drawArt(&art, t: t)
    }

    /// The icon art in icon units (512 space), at time `t`
    private static func drawArt(_ ctx: inout GraphicsContext, t: Double) {
        let drawn = window(t, 288, 1224, routeEasing)
        if drawn > 0 {
            ctx.stroke(route.trimmedPath(from: 0, to: drawn), with: .color(yellow),
                       style: StrokeStyle(lineWidth: 36, lineCap: .round))
        }
        drawStop(&ctx, center: CGPoint(x: 150, y: 360), scale: pop(t, 324))
        drawStop(&ctx, center: CGPoint(x: 250, y: 270), scale: pop(t, 720))
        let bus = window(t, 1116, 1440, overshoot)
        if bus > 0 {
            var c = ctx
            c.translateBy(x: 340, y: 180)
            c.scaleBy(x: bus, y: bus)
            c.translateBy(x: -340, y: -180)
            c.fill(Path(ellipseIn: CGRect(x: 340 - 64, y: 180 - 64, width: 128, height: 128)), with: .color(offWhite))
            c.translateBy(x: 0, y: hop(t))
            drawBusGlyph(&c)
        }
    }

    private static func drawStop(_ ctx: inout GraphicsContext, center: CGPoint, scale: Double) {
        if scale <= 0 { return }
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        c.scaleBy(x: scale, y: scale)
        let circle = Path(ellipseIn: CGRect(x: -25, y: -25, width: 50, height: 50))
        c.fill(circle, with: .color(lake))
        c.stroke(circle, with: .color(offWhite), lineWidth: 14)
    }

    private static func drawBusGlyph(_ ctx: inout GraphicsContext) {
        func rounded(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ r: Double) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }
        func dot(_ x: Double, _ y: Double) -> Path {
            Path(ellipseIn: CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11))
        }
        ctx.fill(rounded(306, 144, 68, 70, 16), with: .color(lake))
        ctx.fill(rounded(315, 155, 50, 28, 6), with: .color(yellow))
        ctx.fill(dot(324, 199), with: .color(offWhite))
        ctx.fill(dot(356, 199), with: .color(offWhite))
        ctx.fill(rounded(312, 211, 13, 10, 3), with: .color(lake))
        ctx.fill(rounded(355, 211, 13, 10, 3), with: .color(lake))
    }
}
