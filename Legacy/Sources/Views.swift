import UIKit

// The pieces every screen is built from, the UIKit versions of App/Sources/UI/Components.swift.

// MARK: - Layout helpers

/// A label in the app's font
func makeLabel(_ text: String, _ size: CGFloat, _ weight: FontWeight = .regular, _ color: UIColor? = nil,
               lines: Int = 1, align: NSTextAlignment = .natural) -> UILabel {
    let label = UILabel()
    label.text = text
    label.font = .brand(size, weight)
    label.textColor = color ?? AC.onBackground
    label.numberOfLines = lines
    label.textAlignment = align
    label.lineBreakMode = lines == 1 ? .byTruncatingTail : .byWordWrapping
    return label
}

/// A row of views
func hstack(_ views: [UIView], spacing: CGFloat = 8, align: UIStackView.Alignment = .center) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views)
    stack.axis = .horizontal
    stack.spacing = spacing
    stack.alignment = align
    return stack
}

/// A column of views
func vstack(_ views: [UIView], spacing: CGFloat = 0, align: UIStackView.Alignment = .fill) -> UIStackView {
    let stack = UIStackView(arrangedSubviews: views)
    stack.axis = .vertical
    stack.spacing = spacing
    stack.alignment = align
    return stack
}

/// Takes the room that's left in a row
func spacer(min: CGFloat = 0) -> UIView {
    let view = UIView()
    view.setContentHuggingPriority(.init(1), for: .horizontal)
    view.setContentCompressionResistancePriority(.init(1), for: .horizontal)
    if min > 0 { view.widthAnchor.constraint(greaterThanOrEqualToConstant: min).isActive = true }
    return view
}

/// Keeps a view at its natural size in a row
@discardableResult
func hug<T: UIView>(_ view: T) -> T {
    view.setContentHuggingPriority(.required, for: .horizontal)
    view.setContentCompressionResistancePriority(.required, for: .horizontal)
    return view
}

/// Lets a view be squeezed first in a row, e.g. a long name
@discardableResult
func squeeze<T: UIView>(_ view: T) -> T {
    view.setContentHuggingPriority(.defaultLow, for: .horizontal)
    view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return view
}

/// Fixes a view's size
@discardableResult
func sized<T: UIView>(_ view: T, width: CGFloat? = nil, height: CGFloat? = nil) -> T {
    view.translatesAutoresizingMaskIntoConstraints = false
    if let width = width { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
    if let height = height { view.heightAnchor.constraint(equalToConstant: height).isActive = true }
    return view
}

/// A view with a minimum height
@discardableResult
func minHeight<T: UIView>(_ view: T, _ height: CGFloat) -> T {
    view.translatesAutoresizingMaskIntoConstraints = false
    view.heightAnchor.constraint(greaterThanOrEqualToConstant: height).isActive = true
    return view
}

/// `content` inside padding
func padded(_ content: UIView, _ insets: UIEdgeInsets) -> UIView {
    let box = UIView()
    box.addSubview(content)
    content.pin(to: box, insets)
    return box
}

/// An icon at its size, in a colour
func iconView(_ icon: Icon, _ color: UIColor, size: CGFloat = 20) -> UIImageView {
    let view = UIImageView(image: icon.image(size))
    view.tintColor = color
    view.contentMode = .center
    sized(view, width: size, height: size)
    hug(view)
    return view
}

extension UIView {
    /// Pins the view's edges to `other`'s, inset
    func pin(to other: UIView, _ insets: UIEdgeInsets = .zero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }

    /// Rounded corners with an optional border
    func rounded(_ radius: CGFloat, border: UIColor? = nil, width: CGFloat = 1) {
        layer.cornerRadius = radius
        if let border = border {
            layer.borderColor = border.cgColor
            layer.borderWidth = width
        }
    }
}

extension UIStackView {
    /// Takes every view out
    func removeAll() {
        for view in arrangedSubviews {
            removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    /// Puts these views in, in place of what was there
    func setViews(_ views: [UIView]) {
        removeAll()
        views.forEach(addArrangedSubview)
    }
}

// MARK: - Taps

/// A button that runs a closure
final class ActionButton: UIButton {
    private var action: () -> Void = {}

    /// A text button, an icon button, or both
    convenience init(title: String? = nil, icon: Icon? = nil, iconSize: CGFloat = 20, color: UIColor? = nil,
                     font: UIFont = .brand(15, .semibold), action: @escaping () -> Void) {
        self.init(type: .system)
        self.action = action
        tintColor = color ?? AC.link
        if let title = title {
            setTitle(title, for: .normal)
            titleLabel?.font = font
            setTitleColor(color ?? AC.link, for: .normal)
        }
        if let icon = icon {
            setImage(icon.image(iconSize), for: .normal)
            if title != nil { titleEdgeInsets = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: -6) }
        }
        addTarget(self, action: #selector(run), for: .touchUpInside)
    }

    /// Changes what a tap does
    func setAction(_ action: @escaping () -> Void) { self.action = action }

    @objc private func run() { action() }
}

/// Makes a whole view tappable, fading it while it's pressed. Buttons inside it still take their own taps.
final class Tappable: UIControl {
    private let action: () -> Void

    init(_ content: UIView, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        addSubview(content)
        content.pin(to: self)
        content.isUserInteractionEnabled = true
        addTarget(self, action: #selector(run), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }

    // Labels and plain views pass their touches up to here; buttons keep theirs
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return hit is UIControl ? hit : self
    }

    @objc private func run() { action() }
}

// MARK: - Components

/// The size of a line badge
enum BadgeSize {
    case sm, md, lg

    var height: CGFloat { self == .sm ? 24 : self == .md ? 28 : 32 }
    var minWidth: CGFloat { self == .sm ? 34 : self == .md ? 40 : 44 }
    var font: CGFloat { self == .sm ? 13 : self == .md ? 15 : 17 }
    var radius: CGFloat { self == .sm ? 6 : self == .md ? 7 : 8 }
}

/// A line's number in its colour; school lines are outlined
func lineBadge(_ line: Line, _ size: BadgeSize = .sm) -> UIView {
    let color = UIColor(hexString: line.color)
    let box = UIView()
    box.backgroundColor = line.school ? AC.surface : color
    box.rounded(size.radius, border: line.school ? color : nil, width: 1.5)
    let label = makeLabel(line.number.count < 2 ? "0" + line.number : line.number, size.font, .bold,
                          line.school ? AC.onBackground : UIColor(hexString: line.textColor), align: .center)
    box.addSubview(label)
    label.translatesAutoresizingMaskIntoConstraints = false
    box.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        box.heightAnchor.constraint(equalToConstant: size.height),
        box.widthAnchor.constraint(greaterThanOrEqualToConstant: size.minWidth),
        label.centerXAnchor.constraint(equalTo: box.centerXAnchor),
        label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        label.leadingAnchor.constraint(greaterThanOrEqualTo: box.leadingAnchor, constant: 6),
    ])
    hug(label)
    hug(box)
    box.accessibilityLabel = line.number
    box.isAccessibilityElement = true
    return box
}

/// The app's card: white (or raised in dark mode), rounded, with a thin border
final class CardView: UIView {
    /// Where the card's pieces go
    let stack = UIStackView()

    init(padding: CGFloat = 16, spacing: CGFloat = 12, vertical: CGFloat = 14) {
        super.init(frame: .zero)
        backgroundColor = AC.surface
        rounded(16, border: AC.border)
        stack.axis = .vertical
        stack.spacing = spacing
        stack.alignment = .fill
        addSubview(stack)
        stack.pin(to: self, UIEdgeInsets(top: vertical, left: padding, bottom: vertical, right: padding))
    }

    convenience init(_ views: [UIView], padding: CGFloat = 16, spacing: CGFloat = 12, vertical: CGFloat = 14) {
        self.init(padding: padding, spacing: spacing, vertical: vertical)
        views.forEach(stack.addArrangedSubview)
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Says the timetables are sample data, when they are
func placeholderBanner() -> UIView? {
    guard AppContainer.shared.data.meta.placeholder else { return nil }
    return banner(L("placeholder_banner"), icon: .info)
}

/// A notice in the banner colours
func banner(_ text: String, icon: Icon) -> UIView {
    let row = hstack([iconView(icon, AC.bannerText, size: 18), makeLabel(text, 14, .regular, AC.bannerText, lines: 0)], spacing: 10, align: .top)
    let box = padded(row, UIEdgeInsets(top: 10, left: 12, bottom: 10, right: 12))
    box.backgroundColor = AC.bannerBg
    box.rounded(12)
    return box
}

/// Section heading with an optional button on the right
func sectionTitle(_ text: String, trailing: UIView? = nil) -> UIView {
    var views: [UIView] = [squeeze(makeLabel(text, 15, .semibold)), spacer()]
    if let trailing = trailing { views.append(hug(trailing)) }
    return padded(minHeight(hstack(views), 30), UIEdgeInsets(top: 10, left: 4, bottom: 0, right: 0))
}

/// A small label in the banner colours, e.g. a walking distance or "Last"
func pill(_ text: String) -> UIView {
    let box = padded(makeLabel(text, 12, .semibold, AC.bannerText), UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6))
    box.backgroundColor = AC.bannerBg
    box.rounded(6)
    return hug(box)
}

/// A hairline between rows, starting after the badge column
func rowDivider(inset: CGFloat = 46) -> UIView {
    let line = UIView()
    line.backgroundColor = AC.divider
    sized(line, height: 1)
    return padded(line, UIEdgeInsets(top: 0, left: inset, bottom: 0, right: 0))
}

/// A star that adds the stop to the favourites or takes it out
func favoriteButton(_ stopId: String, tint: UIColor? = nil) -> UIButton {
    let settings = AppContainer.shared.settings
    let button = ActionButton(icon: settings.isFavorite(stopId) ? .starFill : .star, iconSize: 22,
                              color: settings.isFavorite(stopId) ? AC.star : (tint ?? AC.muted)) {}
    button.setAction { [weak button] in
        settings.toggleFavorite(stopId)
        let on = settings.isFavorite(stopId)
        button?.setImage((on ? Icon.starFill : Icon.star).image(22), for: .normal)
        button?.tintColor = on ? AC.star : (tint ?? AC.muted)
    }
    button.accessibilityLabel = L(settings.isFavorite(stopId) ? "remove_favorite" : "add_favorite")
    return sized(button, width: 44, height: 44)
}

/// An info icon that shows what the operator wrote about a departure
func noteButton(_ note: String, tint: UIColor? = nil, host: UIViewController?) -> UIView {
    let button = ActionButton(icon: .info, iconSize: 18, color: tint ?? AC.link) { [weak host] in
        let alert = UIAlertController(title: L("note_title"), message: note, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: L("close"), style: .cancel))
        host?.present(alert, animated: true)
    }
    button.accessibilityLabel = L("note_show")
    return sized(button, width: 32, height: 32)
}

/// A time, with the live mark before it when it comes from where the bus really is
private func liveMark(_ live: Bool, _ content: UIView) -> UIView {
    guard live else { return content }
    let mark = iconView(.live, AC.live, size: 14)
    mark.accessibilityLabel = L("live_time")
    return hstack([mark, content], spacing: 4)
}

/// One departure: the minutes within the hour, the clock time otherwise; a bus that left is faded
func departureRow(_ dep: Departure, now: LocalDateTime, departed: Bool = false, host: UIViewController?) -> UIView {
    let mins = Schedule.minutesUntil(dep, now: now)
    let clock = Schedule.formatMinutes(dep.minutes)
    let within = !departed && dep.dayOffset == 0 && mins < 60

    var subtitle: [UIView] = [squeeze(makeLabel(departed ? L("departed") : L("towards", dep.direction.headsign.text), 12, .regular, AC.muted))]
    if !departed && dep.last && dep.dayOffset == 0 { subtitle.append(pill(L("last_trip"))) }
    let middle = squeeze(vstack([makeLabel(dep.line.name.text, 15, .medium), hstack(subtitle, spacing: 6)], spacing: 1, align: .leading))

    var right: [UIView] = []
    if departed {
        right.append(makeLabel(clock, 15, .medium, AC.muted))
    } else if within {
        right.append(liveMark(dep.live, makeLabel(mins <= 0 ? L("now") : L("minutes_only", mins), 22, .semibold, dep.live ? AC.live : AC.onBackground)))
        right.append(makeLabel(clock, 12, .regular, AC.muted))
    } else {
        right.append(liveMark(dep.live, makeLabel(clock, 17, .semibold, dep.live ? AC.live : AC.onBackground)))
        if dep.dayOffset > 0 { right.append(makeLabel(L("tomorrow"), 12, .regular, AC.muted)) }
    }

    var views: [UIView] = [lineBadge(dep.line), middle, spacer(min: 4)]
    if let note = dep.note { views.append(noteButton(note, host: host)) }
    views.append(hug(vstack(right, align: .trailing)))
    let row = minHeight(hstack(views, spacing: 12), 60)
    row.alpha = departed ? 0.55 : 1
    return row
}

/// Departures in one list; `previous` is the bus that just left, faded on top. A tap opens the line.
func departureList(_ departures: [Departure], now: LocalDateTime, previous: Departure? = nil, host: UIViewController?) -> UIView {
    if departures.isEmpty && previous == nil {
        return makeLabel(L("no_service"), 14, .regular, AC.muted, lines: 0)
    }
    var rows: [UIView] = []
    func row(_ dep: Departure, departed: Bool) -> UIView {
        Tappable(departureRow(dep, now: now, departed: departed, host: host)) { [weak host] in
            host?.open(.line(dep.line.id, dep.direction.id))
        }
    }
    if let previous = previous { rows.append(row(previous, departed: true)) }
    for (index, dep) in departures.enumerated() {
        if index > 0 || previous != nil { rows.append(rowDivider()) }
        rows.append(row(dep, departed: false))
    }
    if departures.isEmpty {
        rows.append(rowDivider())
        rows.append(padded(makeLabel(L("no_more_today"), 14, .regular, AC.muted, lines: 0), UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)))
    }
    return vstack(rows)
}

/// A stop with its next departures and a star, as on Home
func stopCard(_ stop: Stop, departures: [Departure], now: LocalDateTime, distanceMeters: Double? = nil, host: UIViewController?) -> UIView {
    var subtitle = L("stop_code", stop.id)
    if let meters = distanceMeters { subtitle += " · " + Geo.formatDistance(meters, language: Strings.language) }
    let title = Tappable(vstack([makeLabel(stop.title, 16, .semibold, lines: 0), makeLabel(subtitle, 12, .regular, AC.muted)], spacing: 2)) { [weak host] in
        host?.open(.stop(stop.id))
    }
    let header = hstack([squeeze(title), favoriteButton(stop.id)], spacing: 4)
    return CardView([header, departureList(departures, now: now, host: host)])
}

/// Segmented control in the app's colours
final class SegmentedView: UIView {
    private let onChange: (String) -> Void

    init(options: [(value: String, label: String)], selected: String, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        super.init(frame: .zero)
        backgroundColor = AC.track
        rounded(12)
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 4
        row.distribution = .fillEqually
        for option in options {
            let on = option.value == selected
            let label = makeLabel(option.label, 14, on ? .semibold : .medium, on ? AC.onBackground : AC.ink2, lines: 2, align: .center)
            let cell = padded(label, UIEdgeInsets(top: 6, left: 6, bottom: 6, right: 6))
            cell.backgroundColor = on ? AC.segmentOn : .clear
            cell.rounded(9)
            minHeight(cell, 40)
            if on {
                cell.layer.shadowColor = UIColor.black.cgColor
                cell.layer.shadowOpacity = 0.06
                cell.layer.shadowRadius = 2
                cell.layer.shadowOffset = CGSize(width: 0, height: 1)
            }
            let value = option.value
            row.addArrangedSubview(Tappable(cell) { [weak self] in self?.onChange(value) })
        }
        addSubview(row)
        row.pin(to: self, UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4))
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// A rounded filter chip: dark when selected, outlined otherwise
func chip(selected: Bool, _ content: [UIView], horizontalPadding: CGFloat = 12, action: @escaping () -> Void) -> UIView {
    let row = hstack(content, spacing: 6)
    let box = padded(row, UIEdgeInsets(top: 0, left: horizontalPadding, bottom: 0, right: horizontalPadding))
    sized(box, height: 36)
    box.backgroundColor = selected ? AC.chipOn : AC.surface
    box.rounded(18, border: selected ? nil : AC.border)
    return hug(Tappable(box, action: action))
}

/// A text chip
func textChip(_ text: String, selected: Bool, action: @escaping () -> Void) -> UIView {
    chip(selected: selected, [makeLabel(text, 13, selected ? .semibold : .medium, selected ? AC.chipOnText : AC.ink2)], action: action)
}

/// Views side by side that scroll sideways when they don't fit
func horizontalScroller(_ views: [UIView], spacing: CGFloat = 6, inset: CGFloat = 0) -> UIScrollView {
    let scroll = UIScrollView()
    scroll.showsHorizontalScrollIndicator = false
    let row = hstack(views, spacing: spacing)
    scroll.addSubview(row)
    row.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: inset),
        row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -inset),
        row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
        row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
        row.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
    ])
    return scroll
}

/// The bus drawn on a route strip: a dark rounded square with a light outline and a bus inside
func busMarker() -> UIView {
    let box = UIView()
    box.backgroundColor = AC.onBackground
    box.rounded(9, border: AC.surface, width: 2)
    let icon = iconView(.bus, AC.surface, size: 15)
    box.addSubview(icon)
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.centerXAnchor.constraint(equalTo: box.centerXAnchor).isActive = true
    icon.centerYAnchor.constraint(equalTo: box.centerYAnchor).isActive = true
    return sized(box, width: 26, height: 26)
}

/// The search box: a magnifier, the text, and a button to clear it
final class SearchField: UIView, UITextFieldDelegate {
    /// What's typed
    let field = UITextField()
    private let clear: ActionButton
    private let onChange: (String) -> Void

    init(placeholder: String, compact: Bool = false, onChange: @escaping (String) -> Void) {
        self.onChange = onChange
        clear = ActionButton(icon: .clear, iconSize: 18, color: AC.muted) {}
        super.init(frame: .zero)
        field.font = .brand(compact ? 14 : 16)
        field.textColor = AC.onBackground
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: AC.muted, .font: UIFont.brand(compact ? 14 : 16)])
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.keyboardAppearance = Theme.isDark ? .dark : .light
        field.delegate = self
        field.addTarget(self, action: #selector(edited), for: .editingChanged)
        clear.setAction { [weak self] in
            self?.field.text = ""
            self?.edited()
        }
        clear.accessibilityLabel = L("clear_search")
        clear.isHidden = true
        sized(clear, width: 32, height: 32)
        let row = hstack([iconView(.search, AC.muted, size: 18), field, clear], spacing: 8)
        addSubview(row)
        row.pin(to: self, UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 8))
        sized(self, height: compact ? 44 : 52)
        backgroundColor = compact ? AC.surfaceVariant.withAlphaComponent(0.5) : AC.surface
        rounded(compact ? 10 : 14, border: compact ? nil : AC.border)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The text typed so far
    var text: String { field.text ?? "" }

    @objc private func edited() {
        clear.isHidden = text.isEmpty
        onChange(text)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - Screens

/// Every screen the app can open on top of a tab
enum Route {
    case stop(String)
    case line(String, String?)
    case routeStops(String, String)
    case map(line: String?, stop: String?)
    case announcements
    case settings
    case about

    /// The screen for this route
    func makeScreen() -> UIViewController {
        switch self {
        case .stop(let id): return StopViewController(stopId: id)
        case .line(let id, let direction): return LineViewController(lineId: id, directionId: direction)
        case .routeStops(let id, let direction): return RouteStopsViewController(lineId: id, directionId: direction)
        case .map(let line, let stop): return MapViewController(lineId: line, stopId: stop)
        case .announcements: return AnnouncementsViewController()
        case .settings: return SettingsViewController()
        case .about: return AboutViewController()
        }
    }
}

extension UIViewController {
    /// Opens a screen on top of this one
    func open(_ route: Route) {
        navigationController?.pushViewController(route.makeScreen(), animated: true)
    }

    /// Opens a link in Safari, Maps, Phone or Mail
    func openURL(_ url: URL?) {
        guard let url = url else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

/// A screen that's drawn again every 15 seconds while it shows, and when settings, live trips or
/// announcements change
class Screen: UIViewController {
    /// The navigation bar is hidden on this screen (Home, and the Map tab)
    var hidesNavigationBar: Bool { false }
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AC.background
        // Just the chevron: the system would write "Back" in the phone's language, not the app's
        navigationItem.backBarButtonItem = UIBarButtonItem(title: "", style: .plain, target: nil, action: nil)
        navigationItem.largeTitleDisplayMode = .never
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(hidesNavigationBar, animated: animated)
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.tick() }
        for name in [Notification.Name.settingsChanged, .liveTripsChanged, .announcementsChanged] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.changed(note.name)
            })
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
        timer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
    }

    /// Draws the screen from the current state
    func reload() {}

    /// Every 15 seconds while the screen shows
    func tick() { reload() }

    /// Settings, live trips or announcements changed
    func changed(_ name: Notification.Name) { reload() }

    override var preferredStatusBarStyle: UIStatusBarStyle { Theme.isDark ? .lightContent : .default }
}

/// A screen that's one scrolling column
class ScrollScreen: Screen {
    let scroll = UIScrollView()
    /// The column; `setContent` fills it
    let stack = UIStackView()
    /// Space around the column
    var contentInsets = UIEdgeInsets(top: 4, left: 16, bottom: 20, right: 16)

    override func viewDidLoad() {
        super.viewDidLoad()
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        view.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        scroll.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: contentInsets.left),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -contentInsets.right),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: contentInsets.top),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -contentInsets.bottom),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -(contentInsets.left + contentInsets.right)),
        ])
    }

    /// Fills the column, leaving out the nils
    func setContent(_ views: [UIView?]) {
        stack.setViews(views.compactMap { $0 })
    }
}

/// A navigation stack whose status bar follows the theme
final class NavigationController: UINavigationController {
    override var preferredStatusBarStyle: UIStatusBarStyle { Theme.isDark ? .lightContent : .default }
}
