import UIKit

// MARK: - Images

/// Downloads the announcements' posters once and keeps them in memory
enum ImageLoader {
    private static let cache = NSCache<NSURL, UIImage>()

    /// The picture at `url`, on the main thread; nil when it can't be had
    static func load(_ url: URL, _ done: @escaping (UIImage?) -> Void) {
        if let hit = cache.object(forKey: url as NSURL) { return done(hit) }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap(UIImage.init(data:))
            if let image = image { cache.setObject(image, forKey: url as NSURL) }
            DispatchQueue.main.async { done(image) }
        }.resume()
    }
}

/// A picture from the web, as tall as its proportions need up to `maxHeight`
final class RemoteImageView: UIView {
    private let imageView = UIImageView()
    private let status = makeLabel("", 13, .regular, AC.muted, align: .center)
    private let spinner = UIActivityIndicatorView(style: .gray)
    private var height: NSLayoutConstraint!
    private let maxHeight: CGFloat

    init(url: URL, maxHeight: CGFloat, placeholderHeight: CGFloat = 160) {
        self.maxHeight = maxHeight
        super.init(frame: .zero)
        backgroundColor = AC.surfaceVariant
        clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        for v in [imageView, status, spinner] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        imageView.pin(to: self)
        NSLayoutConstraint.activate([
            status.centerXAnchor.constraint(equalTo: centerXAnchor),
            status.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        height = heightAnchor.constraint(equalToConstant: placeholderHeight)
        height.isActive = true
        spinner.startAnimating()
        ImageLoader.load(url) { [weak self] image in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            guard let image = image else {
                self.status.text = L("image_unavailable")
                return
            }
            self.imageView.image = image
            self.updateHeight()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The picture that came, if any
    var image: UIImage? { imageView.image }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateHeight()
    }

    private func updateHeight() {
        guard let image = image, image.size.width > 0, bounds.width > 0 else { return }
        let wanted = min(maxHeight, bounds.width * image.size.height / image.size.width)
        if abs(height.constant - wanted) > 0.5 { height.constant = wanted }
    }
}

/// "7 Νοεμβρίου 2026"
func publishedDate(_ announcement: Announcement) -> String {
    let formatter = DateFormatter()
    formatter.locale = appLocale
    formatter.setLocalizedDateFormatFromTemplate("dMMMMyyyy")
    return formatter.string(from: announcement.publishedAt)
}

/// Compact row for the Home screen: thumbnail, title, date
func announcementRow(_ announcement: Announcement) -> UIView {
    var views: [UIView] = []
    if let url = announcement.image.flatMap(URL.init(string:)) {
        let thumb = RemoteImageView(url: url, maxHeight: 56, placeholderHeight: 56)
        thumb.rounded(10)
        sized(thumb, width: 56)
        views.append(thumb)
    }
    views.append(squeeze(vstack([makeLabel(announcement.title, 15, .semibold, lines: 2), makeLabel(publishedDate(announcement), 13, .regular, AC.muted)], spacing: 2)))
    views.append(spacer())
    return CardView([hstack(views, spacing: 12)], padding: 12)
}

// MARK: - Announcements

/// The operator's announcements, with their posters full screen on a tap
final class AnnouncementsViewController: ScrollScreen {
    private let store = AppContainer.shared.announcements
    private let refresher = UIRefreshControl()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("announcements")
        refresher.addTarget(self, action: #selector(pulled), for: .valueChanged)
        scroll.refreshControl = refresher
        let refresh = ActionButton(icon: .refresh, iconSize: 22, color: AC.link) { [weak self] in self?.store.refresh(force: true) }
        refresh.accessibilityLabel = L("refresh")
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: sized(refresh, width: 40, height: 44))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        store.refresh()
    }

    @objc private func pulled() { store.refresh(force: true) }

    // Only announcements change what's here: no need to rebuild the posters every 15 seconds
    override func tick() {}

    override func changed(_ name: Notification.Name) {
        if name == .announcementsChanged { reload() }
    }

    override func reload() {
        refresher.endRefreshing()
        guard let list = store.announcements else {
            let spinner = UIActivityIndicatorView(style: Theme.isDark ? .white : .gray)
            spinner.startAnimating()
            setContent([padded(spinner, UIEdgeInsets(top: 60, left: 0, bottom: 0, right: 0))])
            return
        }
        var views: [UIView] = []
        if store.failed {
            views.append(makeLabel(L(list.isEmpty ? "announcements_offline_empty" : "announcements_offline"), 14, .regular, AC.muted, lines: 0))
        } else if list.isEmpty {
            views.append(makeLabel(L("announcements_none"), 14, .regular, AC.muted, lines: 0))
        }
        views += list.map(card)
        setContent(views)
    }

    private func card(_ announcement: Announcement) -> UIView {
        let card = CardView()
        card.stack.addArrangedSubview(vstack([makeLabel(announcement.title, 17, .semibold, lines: 0),
                                              makeLabel(publishedDate(announcement), 13, .regular, AC.muted)], spacing: 2))
        if let url = announcement.image.flatMap(URL.init(string:)) {
            let picture = RemoteImageView(url: url, maxHeight: 420)
            picture.rounded(12)
            picture.accessibilityLabel = L("announcement_image", announcement.title)
            card.stack.addArrangedSubview(Tappable(picture) { [weak self, weak picture] in
                guard let image = picture?.image else { return }
                let viewer = ImageViewerController(image: image)
                viewer.modalPresentationStyle = .fullScreen
                self?.present(viewer, animated: true)
            })
        }
        if !announcement.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let text = makeLabel("", 15, .regular, nil, lines: 0)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            text.attributedText = NSAttributedString(string: announcement.text, attributes: [.paragraphStyle: style, .font: UIFont.brand(15), .foregroundColor: AC.onBackground])
            card.stack.addArrangedSubview(text)
        }
        if let url = URL(string: announcement.url) {
            let button = ActionButton(title: L("open_website")) { [weak self] in self?.openURL(url) }
            button.contentHorizontalAlignment = .leading
            card.stack.addArrangedSubview(button)
        }
        return card
    }
}

/// A picture full screen: pinch to zoom, drag to pan, double tap to reset
final class ImageViewerController: UIViewController, UIScrollViewDelegate {
    private let scroll = UIScrollView()
    private let imageView: UIImageView

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        scroll.delegate = self
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        view.addSubview(scroll)
        scroll.pin(to: view)
        imageView.contentMode = .scaleAspectFit
        scroll.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(reset))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)

        let close = ActionButton(icon: .close, iconSize: 18, color: .white) { [weak self] in self?.dismiss(animated: true) }
        close.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        close.rounded(22)
        close.accessibilityLabel = L("close")
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)
        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    @objc private func reset() { scroll.setZoomScale(1, animated: true) }
}

// MARK: - Settings

/// Opened from the gear on Home: language, theme and voice, with "About this app" one level down
final class SettingsViewController: ScrollScreen {
    private let settings = AppContainer.shared.settings

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("tab_settings")
        stack.spacing = 8
    }

    // Nothing here changes by itself
    override func tick() {}

    override func reload() {
        let language = SegmentedView(options: [(value: "el", label: "Ελληνικά"), (value: "en", label: "English")],
                                     selected: settings.language) { [weak self] value in self?.settings.language = value }
        let theme = SegmentedView(options: [(value: ThemeMode.system.rawValue, label: L("theme_system")),
                                            (value: ThemeMode.light.rawValue, label: L("theme_light")),
                                            (value: ThemeMode.dark.rawValue, label: L("theme_dark"))],
                                  selected: settings.theme.rawValue) { [weak self] value in
            self?.settings.theme = ThemeMode(rawValue: value) ?? .system
        }
        let toggle = UISwitch()
        toggle.isOn = settings.voice
        toggle.onTintColor = AC.primary
        toggle.addTarget(self, action: #selector(voiceToggled(_:)), for: .valueChanged)
        let voice = CardView([hstack([squeeze(makeLabel(L("voice_title"), 15, .medium, lines: 0)), spacer(), hug(toggle)], spacing: 12)])
        let about = Tappable(CardView([hstack([iconView(.info, AC.ink2), squeeze(makeLabel(L("about_app"), 15, .medium)), spacer(),
                                               iconView(.chevronRight, AC.muted, size: 14)], spacing: 12)])) { [weak self] in
            self?.open(.about)
        }
        setContent([sectionTitle(L("language")), language,
                    padded(sectionTitle(L("theme")), UIEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)), theme,
                    padded(voice, UIEdgeInsets(top: 16, left: 0, bottom: 0, right: 0)),
                    padded(about, UIEdgeInsets(top: 16, left: 0, bottom: 0, right: 0))])
    }

    @objc private func voiceToggled(_ toggle: UISwitch) {
        settings.voice = toggle.isOn
    }
}

/// How to reach Αστικό ΚΤΕΛ Καστοριάς, who made the app, and the fine print
final class AboutViewController: ScrollScreen {
    private let phone = "+30 24670 83959"
    private let fax = "+30 24670 21364"
    private let email = "astikast@otenet.gr"
    private let teamSite = "https://kastoria-dev-core.github.io/"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("about_app")
        stack.spacing = 8
    }

    override func tick() {}

    override func reload() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let mark = UIImageView(image: UIImage(named: "AppMark")?.withRenderingMode(.alwaysTemplate))
        mark.tintColor = AC.offWhite
        mark.contentMode = .scaleAspectFit
        let tile = padded(mark, UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        tile.backgroundColor = AC.lake
        tile.rounded(14)
        sized(tile, width: 64, height: 64)
        let top = padded(vstack([tile, makeLabel(L("app_title"), 17, .semibold), makeLabel(L("version_label", version), 13, .regular, AC.muted)], spacing: 6, align: .center),
                         UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0))

        let address = L("contact_address")
        let contact = CardView(spacing: 0)
        contact.stack.addArrangedSubview(row(L("contact_address_label"), address) { [weak self] in
            let query = address.replacingOccurrences(of: "\n", with: " ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            self?.openURL(URL(string: "http://maps.apple.com/?q=\(query)"))
        })
        contact.stack.addArrangedSubview(rowDivider(inset: 0))
        contact.stack.addArrangedSubview(row(L("contact_phone"), phone) { [weak self] in
            guard let self = self else { return }
            self.openURL(URL(string: "tel:" + self.phone.replacingOccurrences(of: " ", with: "")))
        })
        contact.stack.addArrangedSubview(rowDivider(inset: 0))
        contact.stack.addArrangedSubview(row(L("contact_fax"), fax, action: nil))
        contact.stack.addArrangedSubview(rowDivider(inset: 0))
        contact.stack.addArrangedSubview(row(L("contact_email"), email) { [weak self] in
            guard let self = self else { return }
            self.openURL(URL(string: "mailto:" + self.email))
        })

        let people = CardView(spacing: 0)
        for (index, name) in Strings.array("contributors").enumerated() {
            if index > 0 { people.stack.addArrangedSubview(rowDivider(inset: 0)) }
            people.stack.addArrangedSubview(padded(makeLabel(name, 15, .regular, nil, lines: 0), UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)))
        }
        people.stack.addArrangedSubview(rowDivider(inset: 0))
        people.stack.addArrangedSubview(row(L("website"), "kastoria-dev-core.github.io") { [weak self] in
            guard let self = self else { return }
            self.openURL(URL(string: self.teamSite))
        })

        let fine = padded(vstack([makeLabel(L("official_app"), 13, .regular, AC.muted, lines: 0),
                                  makeLabel(L("map_attribution"), 12, .regular, AC.muted, lines: 0),
                                  makeLabel(L("font_attribution"), 12, .regular, AC.muted, lines: 0)], spacing: 8),
                          UIEdgeInsets(top: 12, left: 4, bottom: 12, right: 4))
        setContent([top, placeholderBanner(), sectionTitle(L("contact")), contact, sectionTitle(L("contributors")), people, fine])
    }

    private func row(_ label: String, _ value: String, action: (() -> Void)?) -> UIView {
        let row = hstack([hug(makeLabel(label, 15, .regular, AC.muted)), spacer(min: 8),
                          squeeze(makeLabel(value, 15, .medium, action == nil ? AC.onBackground : AC.link, lines: 0, align: .right))], spacing: 12, align: .top)
        let box = padded(row, UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0))
        guard let action = action else { return box }
        return Tappable(box, action: action)
    }
}
