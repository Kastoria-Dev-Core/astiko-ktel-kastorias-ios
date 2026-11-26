import MapKit
import UIKit

/// Where the map opens: the Αφετηρία (terminal) stop, id 16001
private let terminal = CLLocationCoordinate2D(latitude: 40.52140470548326, longitude: 21.26186932879127)
/// The streets around, when the map opens on the terminal or the user
private let townDistance: CLLocationDistance = 1_100
/// Further out than this, the stops are dots and the buses small
private let farDistance: CLLocationDistance = 6_000
/// How far past the outermost stops the map can be panned, in degrees (about 8 km), on iOS 13+
private let areaMargin = 0.07

extension LatLng {
    /// The point for MapKit
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// A stop on the map
final class StopAnnotation: NSObject, MKAnnotation {
    let stop: Stop
    let coordinate: CLLocationCoordinate2D

    init(_ stop: Stop) {
        self.stop = stop
        coordinate = CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng)
    }
}

/// A bus on the map; its position moves with each refresh
final class BusAnnotation: NSObject, MKAnnotation {
    var bus: BusOnMap
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(_ bus: BusOnMap) {
        self.bus = bus
        coordinate = CLLocationCoordinate2D(latitude: bus.lat, longitude: bus.lng)
    }
}

/// A line's path, drawn in its colour
final class RoutePolyline: MKPolyline {
    var color: UIColor = .gray
}

/// Touches on its empty parts go through to the map underneath
final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        if hit === self || hit is UIStackView { return nil }
        if type(of: hit) == UIView.self && (hit.backgroundColor == nil || hit.backgroundColor == .clear) { return nil }
        return hit
    }
}

// MARK: - Pins

/// The image tinted in a colour
private func tinted(_ image: UIImage, _ color: UIColor) -> UIImage {
    UIGraphicsImageRenderer(size: image.size).image { _ in
        let rect = CGRect(origin: .zero, size: image.size)
        image.draw(in: rect)
        color.setFill()
        UIRectFillUsingBlendMode(rect, .sourceIn)
    }
}

private var pinCache: [String: UIImage] = [:]

/// A stop: a dot from far away, a pin with a bus from close by, the open one bigger and yellow
private func stopPin(open: Bool, far: Bool) -> UIImage {
    let key = "stop-\(open)-\(far)"
    if let hit = pinCache[key] { return hit }
    let image: UIImage
    if !open && far {
        image = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22)).image { _ in
            let dot = UIBezierPath(ovalIn: CGRect(x: 7, y: 7, width: 8, height: 8))
            AC.lake.setFill()
            dot.fill()
            UIColor.white.setStroke()
            dot.lineWidth = 1.25
            dot.stroke()
        }
    } else {
        let size: CGFloat = open ? 30 : 22
        let canvas = size + 6
        image = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas)).image { _ in
            let disc = UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: size, height: size))
            (open ? AC.routeYellow : AC.lake).setFill()
            disc.fill()
            UIColor.white.setStroke()
            disc.lineWidth = 2
            disc.stroke()
            let glyph = size * 0.55
            tinted(Icon.bus.image(glyph), open ? UIColor(hex: 0x10212B) : .white)
                .draw(in: CGRect(x: (canvas - glyph) / 2, y: (canvas - glyph) / 2, width: glyph, height: glyph))
        }
    }
    pinCache[key] = image
    return image
}

/// A bus: a white disc ringed in the line's colour with a bus and the number; from far just the number
private func busPin(_ line: Line, small: Bool) -> UIImage {
    let key = "bus-\(line.id)-\(small)"
    if let hit = pinCache[key] { return hit }
    let color = UIColor(hexString: line.color)
    let number = (line.number.count < 2 ? "0" + line.number : line.number) as NSString
    let image: UIImage
    if small {
        image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { _ in
            let disc = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 22, height: 22))
            color.setFill()
            disc.fill()
            UIColor.white.setStroke()
            disc.lineWidth = 1.5
            disc.stroke()
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.brand(10, .bold), .foregroundColor: UIColor(hexString: line.textColor)]
            let size = number.size(withAttributes: attrs)
            number.draw(at: CGPoint(x: 12 - size.width / 2, y: 12 - size.height / 2), withAttributes: attrs)
        }
    } else {
        image = UIGraphicsImageRenderer(size: CGSize(width: 38, height: 38)).image { _ in
            let outer = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 36, height: 36))
            UIColor.white.setFill()
            outer.fill()
            let ring = UIBezierPath(ovalIn: CGRect(x: 3.25, y: 3.25, width: 31.5, height: 31.5))
            ring.lineWidth = 2.5
            color.setStroke()
            ring.stroke()
            tinted(Icon.bus.image(12), color).draw(in: CGRect(x: 13, y: 7, width: 12, height: 12))
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.brand(11, .bold), .foregroundColor: color]
            let size = number.size(withAttributes: attrs)
            number.draw(at: CGPoint(x: 19 - size.width / 2, y: 18), withAttributes: attrs)
        }
    }
    pinCache[key] = image
    return image
}

// MARK: - The map

/// The map: every stop, the chosen line along the streets, and the buses, real or estimated. `lineId` shows
/// just that line, `stopId` opens that stop's card. The Map tab itself has neither.
final class MapViewController: Screen, MKMapViewDelegate {
    private let initialLineId: String?
    private let initialStopId: String?
    private let container = AppContainer.shared

    private var lineFilter: String?
    private var openStopId: String?
    private var far = false
    private var showNames = false
    private var buses: [BusOnMap] = []
    private var user: Coords?
    private var locating = false
    private var locationMessage: String?
    private var busTimer: Timer?
    private var stopVoice: StopVoice?
    private var placedInitially = false

    private let mapView = MKMapView()
    private let filters = UIView()
    private let topOverlay = PassthroughView()
    private let bottomOverlay = PassthroughView()
    private var busAnnotations: [String: BusAnnotation] = [:]

    init(lineId: String?, stopId: String?) {
        initialLineId = lineId
        initialStopId = stopId
        lineFilter = lineId
        openStopId = stopId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The map tab itself, rather than a map opened from a stop or a line
    private var isTab: Bool { initialLineId == nil && initialStopId == nil }

    override var hidesNavigationBar: Bool { isTab }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("tab_map")
        filters.backgroundColor = AC.background
        for v in [filters, mapView, topOverlay, bottomOverlay] {
            v.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(v)
        }
        NSLayoutConstraint.activate([
            filters.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filters.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filters.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            filters.heightAnchor.constraint(equalToConstant: 58),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.topAnchor.constraint(equalTo: filters.bottomAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            topOverlay.leadingAnchor.constraint(equalTo: mapView.leadingAnchor, constant: 12),
            topOverlay.trailingAnchor.constraint(equalTo: mapView.trailingAnchor, constant: -12),
            topOverlay.topAnchor.constraint(equalTo: mapView.topAnchor, constant: 10),
            bottomOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomOverlay.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])

        mapView.delegate = self
        mapView.showsCompass = true
        mapView.showsScale = true
        mapView.showsPointsOfInterest = false
        mapView.showsUserLocation = container.location.hasPermission
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "stop")
        mapView.register(MKAnnotationView.self, forAnnotationViewWithReuseIdentifier: "bus")
        if #available(iOS 13.0, *) { limitToNetwork() }
        mapView.setCamera(MKMapCamera(lookingAtCenter: terminal, fromDistance: townDistance, pitch: 0, heading: 0), animated: false)

        buildFilters()
        showStops()
        showRoutes()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !placedInitially {
            placedInitially = true
            if let stop = container.data.stop(initialStopId) {
                focus(stop)
            } else if let line = container.data.line(lineFilter) {
                fit(line)
            }
        }
        refreshBuses()
        busTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refreshBuses() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        busTimer?.invalidate()
        busTimer = nil
        stopVoice?.stop()
    }

    /// The overlays: the timetable link, live or estimated, and the stop card or the location button
    override func reload() {
        guard isViewLoaded else { return }
        buildTop()
        buildBottom()
    }

    // MARK: - Filters

    private func buildFilters() {
        filters.subviews.forEach { $0.removeFromSuperview() }
        let items = container.data.lines.map { line -> UIView in
            let on = lineFilter == line.id
            let color = UIColor(hexString: line.color)
            if showNames {
                let number = makeLabel(line.number.count < 2 ? "0" + line.number : line.number, 14, .bold, on ? UIColor(hexString: line.textColor) : color)
                let name = makeLabel(line.name.text, 14, .medium, on ? UIColor(hexString: line.textColor) : AC.onBackground)
                let box = padded(hstack([number, name], spacing: 6), UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14))
                sized(box, height: 40)
                box.backgroundColor = on ? color : AC.surface
                box.rounded(20, border: on ? color : AC.border)
                return hug(Tappable(box) { [weak self] in self?.setLineFilter(on ? nil : line.id) })
            }
            // Just the badge; the chosen one gets a short bar underneath, like a tab, and the others step back
            let bar = UIView()
            bar.backgroundColor = on ? color : .clear
            bar.rounded(1.5)
            sized(bar, width: 20, height: 3)
            let column = vstack([lineBadge(line, .md), bar], spacing: 4, align: .center)
            let box = padded(column, UIEdgeInsets(top: 7, left: 4, bottom: 0, right: 4))
            box.alpha = lineFilter == nil || on ? 1 : 0.45
            return hug(Tappable(box) { [weak self] in self?.setLineFilter(on ? nil : line.id) })
        }
        let scroller = horizontalScroller(items, spacing: 8, inset: 12)
        let list = ActionButton(icon: .list, iconSize: 18, color: showNames ? AC.background : AC.onBackground) { [weak self] in
            guard let self = self else { return }
            self.showNames.toggle()
            self.buildFilters()
        }
        list.backgroundColor = showNames ? AC.onBackground : AC.surface
        list.rounded(12, border: showNames ? AC.onBackground : AC.border)
        list.accessibilityLabel = L(showNames ? "view_numbers" : "view_names")
        for v in [scroller, list] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            filters.addSubview(v)
        }
        NSLayoutConstraint.activate([
            scroller.leadingAnchor.constraint(equalTo: filters.leadingAnchor),
            scroller.topAnchor.constraint(equalTo: filters.topAnchor, constant: 8),
            scroller.bottomAnchor.constraint(equalTo: filters.bottomAnchor, constant: -8),
            list.leadingAnchor.constraint(equalTo: scroller.trailingAnchor, constant: 4),
            list.trailingAnchor.constraint(equalTo: filters.trailingAnchor, constant: -12),
            list.centerYAnchor.constraint(equalTo: filters.centerYAnchor),
            list.widthAnchor.constraint(equalToConstant: 40),
            list.heightAnchor.constraint(equalToConstant: 40),
        ])
        // Keep the chosen line in view
        if let selected = lineFilter, let index = container.data.lines.firstIndex(where: { $0.id == selected }) {
            view.layoutIfNeeded()
            let item = items[index]
            scroller.scrollRectToVisible(item.convert(item.bounds, to: scroller).insetBy(dx: -40, dy: 0), animated: false)
        }
    }

    private func setLineFilter(_ id: String?) {
        lineFilter = id
        let data = container.data
        if let line = data.line(id) {
            fit(line)
            // Don't keep a card open for a stop the filter just hid
            if let open = openStopId, !data.lineStopIds(line).contains(open) { closeStop() }
        } else {
            mapView.setCamera(MKMapCamera(lookingAtCenter: home, fromDistance: townDistance, pitch: 0, heading: 0), animated: true)
        }
        buildFilters()
        showStops()
        showRoutes()
        refreshBuses()
        reload()
    }

    // MARK: - What's on the map

    private func showStops() {
        mapView.removeAnnotations(mapView.annotations.filter { $0 is StopAnnotation })
        let data = container.data
        let stops: [Stop]
        if let line = data.line(lineFilter) {
            let ids = data.lineStopIds(line)
            stops = data.stops.filter { ids.contains($0.id) }
        } else {
            stops = data.stops
        }
        mapView.addAnnotations(stops.map { StopAnnotation($0) })
    }

    private func showRoutes() {
        mapView.removeOverlays(mapView.overlays)
        guard let line = container.data.line(lineFilter) else { return }
        let data = container.data
        // Both directions: outbound and return often take different streets
        let paths = line.directions.flatMap { d in [data.directionPath(line, d.id)] + data.branchPaths(line, d.id) }
        for path in paths where path.count > 1 {
            var coords = path.map { $0.coordinate }
            let count = coords.count
            let polyline = RoutePolyline(coordinates: &coords, count: count)
            polyline.color = UIColor(hexString: line.color)
            mapView.addOverlay(polyline)
        }
    }

    private func refreshBuses() {
        container.liveBuses.buses { [weak self] live in
            guard let self = self else { return }
            let all = busesOnMap(data: self.container.data, estimated: self.container.busEstimator.estimate(.now), live: live)
            self.buses = all.filter { self.lineFilter == nil || $0.line.id == self.lineFilter }
            var keep = Set<String>()
            for bus in self.buses {
                keep.insert(bus.id)
                if let annotation = self.busAnnotations[bus.id] {
                    annotation.bus = bus
                    UIView.animate(withDuration: 0.8) {
                        annotation.coordinate = CLLocationCoordinate2D(latitude: bus.lat, longitude: bus.lng)
                    }
                } else {
                    let annotation = BusAnnotation(bus)
                    self.busAnnotations[bus.id] = annotation
                    self.mapView.addAnnotation(annotation)
                }
            }
            let gone = self.busAnnotations.filter { !keep.contains($0.key) }
            self.mapView.removeAnnotations(Array(gone.values))
            gone.keys.forEach { self.busAnnotations.removeValue(forKey: $0) }
            self.buildTop()
        }
    }

    /// The pins drawn again after zooming past `farDistance` or opening a stop
    private func refreshPins() {
        for annotation in mapView.annotations {
            guard let view = mapView.view(for: annotation) else { continue }
            if let stop = annotation as? StopAnnotation {
                view.image = stopPin(open: stop.stop.id == openStopId, far: far && lineFilter == nil)
                view.layer.zPosition = stop.stop.id == openStopId ? 1 : 0
            } else if let bus = annotation as? BusAnnotation {
                view.image = busPin(bus.bus.line, small: far)
            }
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let stop = annotation as? StopAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "stop", for: annotation)
            view.image = stopPin(open: stop.stop.id == openStopId, far: far && lineFilter == nil)
            view.canShowCallout = false
            view.layer.zPosition = stop.stop.id == openStopId ? 1 : 0
            view.accessibilityLabel = stop.stop.title
            return view
        }
        if let bus = annotation as? BusAnnotation {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "bus", for: annotation)
            view.image = busPin(bus.bus.line, small: far)
            view.canShowCallout = false
            view.layer.zPosition = 2
            view.layer.shadowColor = UIColor.black.cgColor
            view.layer.shadowOpacity = 0.3
            view.layer.shadowRadius = 2
            view.layer.shadowOffset = CGSize(width: 0, height: 1)
            view.accessibilityLabel = "\(bus.bus.line.number) → \(bus.bus.direction.headsign.text)"
            return view
        }
        return nil
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation else { return }
        mapView.deselectAnnotation(annotation, animated: false)
        if let stop = annotation as? StopAnnotation {
            openStop(stop.stop.id)
        } else if let bus = annotation as? BusAnnotation {
            open(.line(bus.bus.line.id, bus.bus.direction.id))
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(overlay: overlay)
        renderer.strokeColor = (overlay as? RoutePolyline)?.color ?? .gray
        renderer.lineWidth = 5
        renderer.lineCap = .round
        renderer.lineJoin = .round
        return renderer
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        let nowFar = mapView.camera.altitude > farDistance
        if nowFar != far {
            far = nowFar
            refreshPins()
        }
    }

    @available(iOS 13.0, *)
    private func limitToNetwork() {
        let stops = container.data.stops
        let lats = stops.map { $0.lat }
        let lngs = stops.map { $0.lng }
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: maxLat - minLat + 2 * areaMargin, longitudeDelta: maxLng - minLng + 2 * areaMargin))
        mapView.cameraBoundary = MKMapView.CameraBoundary(coordinateRegion: region)
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 150, maxCenterCoordinateDistance: 80_000)
    }

    // MARK: - Overlays

    private func buildTop() {
        topOverlay.subviews.forEach { $0.removeFromSuperview() }
        var items: [UIView] = []
        if let line = container.data.line(lineFilter) {
            let label = makeLabel(L("line_timetable") + " ›", 12, .semibold, AC.link)
            let box = padded(label, UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10))
            box.backgroundColor = AC.surface
            box.rounded(12, border: AC.border)
            items.append(hug(Tappable(box) { [weak self] in self?.open(.line(line.id, nil)) }))
        }
        if !buses.isEmpty {
            let label = makeLabel(L(buses.allSatisfy { $0.live } ? "buses_live_short" : "buses_estimated_short"), 12, .regular, AC.muted)
            let box = padded(label, UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10))
            box.backgroundColor = AC.surface.withAlphaComponent(0.92)
            box.rounded(12, border: AC.border)
            items.append(hug(box))
        }
        items.append(spacer())
        let row = hstack(items, spacing: 8)
        topOverlay.addSubview(row)
        row.pin(to: topOverlay)
    }

    private func buildBottom() {
        bottomOverlay.subviews.forEach { $0.removeFromSuperview() }
        let content: UIView
        if let stop = container.data.stop(openStopId) {
            content = padded(stopSheet(stop), UIEdgeInsets(top: 0, left: 8, bottom: 12, right: 8))
        } else {
            let message: UIView
            if let text = locationMessage {
                let box = padded(makeLabel(text, 14, .regular, nil, lines: 0), UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
                box.backgroundColor = AC.surface
                box.rounded(12, border: AC.border)
                box.layer.shadowColor = UIColor.black.cgColor
                box.layer.shadowOpacity = 0.12
                box.layer.shadowRadius = 6
                box.layer.shadowOffset = CGSize(width: 0, height: 2)
                message = squeeze(box)
            } else {
                message = spacer()
            }
            // Bottom right, where the thumb is
            let button = ActionButton(icon: .location, iconSize: 22, color: locating ? AC.muted : AC.primary) { [weak self] in self?.locate() }
            button.isEnabled = !locating
            button.backgroundColor = AC.surface
            button.rounded(16, border: AC.border)
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.15
            button.layer.shadowRadius = 6
            button.layer.shadowOffset = CGSize(width: 0, height: 2)
            button.accessibilityLabel = L("my_location")
            content = padded(hstack([message, sized(button, width: 56, height: 56)], spacing: 12, align: .bottom),
                             UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16))
        }
        bottomOverlay.addSubview(content)
        content.pin(to: bottomOverlay)
    }

    /// The card of a tapped stop: its next buses, all departures, and walking directions
    private func stopSheet(_ stop: Stop) -> UIView {
        let now = LocalDateTime.now
        let departures = container.schedule.nextDepartures(stop.id, now: now, limit: 3, live: container.liveTrips)
        let voice = stopVoice ?? StopVoice()
        stopVoice = voice
        let close = sized(ActionButton(icon: .close, iconSize: 18, color: AC.ink2) { [weak self] in self?.closeStop() }, width: 44, height: 44)
        close.accessibilityLabel = L("close")
        let titles = squeeze(padded(vstack([makeLabel(stop.title, 18, .semibold, lines: 0), makeLabel(L("stop_code", stop.id), 13, .regular, AC.muted)], spacing: 2),
                                    UIEdgeInsets(top: 6, left: 0, bottom: 0, right: 0)))
        let header = hstack([titles, spacer(), voice.button(host: self) { [weak self] in self?.reload() }, close], spacing: 0, align: .top)

        let all = makeLabel(L("all_departures"), 15, .semibold, .white, align: .center)
        let allBox = padded(all, UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8))
        allBox.backgroundColor = AC.primary
        allBox.rounded(12)
        minHeight(allBox, 48)
        let allButton = Tappable(allBox) { [weak self] in self?.open(.stop(stop.id)) }
        let directions = ActionButton(title: L("directions"), icon: .walk, iconSize: 18, color: AC.primary) { [weak self] in
            // Walking directions in Apple Maps
            self?.openURL(URL(string: "http://maps.apple.com/?daddr=\(stop.lat),\(stop.lng)&dirflg=w"))
        }
        directions.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 20)
        directions.rounded(12, border: AC.outline)
        minHeight(directions, 48)
        let buttons = hstack([allButton, hug(directions)], spacing: 8, align: .fill)

        let column = vstack([header, departureList(departures, now: now, host: self), buttons], spacing: 8)
        let card = padded(column, UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 8))
        card.backgroundColor = AC.surface
        card.rounded(20, border: AC.border)
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.18
        card.layer.shadowRadius = 10
        card.layer.shadowOffset = CGSize(width: 0, height: 3)

        voice.update(stopName: stop.name.text, departures: departures, now: now)
        return card
    }

    private func openStop(_ id: String) {
        if openStopId != id {
            stopVoice?.stop()
            // A new card for each stop, so the speaker choice doesn't carry over
            stopVoice = nil
        }
        openStopId = id
        refreshPins()
        reload()
    }

    private func closeStop() {
        stopVoice?.stop()
        stopVoice = nil
        openStopId = nil
        refreshPins()
        reload()
    }

    // MARK: - Camera

    /// The user's position when it's somewhere the map can show, otherwise the terminal
    private var home: CLLocationCoordinate2D {
        guard let user = user else { return terminal }
        let nearest = container.data.stops.map { Geo.distanceMeters(user.lat, user.lng, $0.lat, $0.lng) }.min() ?? .infinity
        return nearest < 8_000 ? CLLocationCoordinate2D(latitude: user.lat, longitude: user.lng) : terminal
    }

    private func focus(_ stop: Stop) {
        mapView.setCamera(MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng), fromDistance: 1_500, pitch: 0, heading: 0), animated: false)
    }

    /// Both directions of a line, with some room around them
    private func fit(_ line: Line) {
        let points = line.directions.flatMap { container.data.directionStops(line, $0.id) }
        guard let minLat = points.map({ $0.lat }).min(), let maxLat = points.map({ $0.lat }).max(),
              let minLng = points.map({ $0.lng }).min(), let maxLng = points.map({ $0.lng }).max() else { return }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.006, (maxLat - minLat) * 1.35), longitudeDelta: max(0.006, (maxLng - minLng) * 1.35)))
        mapView.setRegion(region, animated: placedInitially && isViewLoaded && view.window != nil)
    }

    /// Each tap on the Map tab: all stops, on the user, asking for the location the first time if needed
    func tabTapped() {
        guard isTab else { return }
        loadViewIfNeeded()
        if lineFilter != nil {
            lineFilter = nil
            buildFilters()
            showStops()
            showRoutes()
            refreshBuses()
        }
        if openStopId != nil { closeStop() }
        locationMessage = nil
        reload()
        mapView.setCamera(MKMapCamera(lookingAtCenter: home, fromDistance: townDistance, pitch: 0, heading: 0), animated: true)
        guard !container.location.isDenied else { return }
        container.location.current { [weak self] result in
            guard let self = self, case .success(let coords) = result else { return }
            self.user = coords
            self.mapView.showsUserLocation = true
            // Only if still on all lines: picking a line while waiting for the fix wins
            if self.lineFilter == nil {
                self.mapView.setCamera(MKMapCamera(lookingAtCenter: self.home, fromDistance: townDistance, pitch: 0, heading: 0), animated: true)
            }
        }
    }

    /// The location button: to the user, or a message saying why not
    private func locate() {
        locating = true
        locationMessage = nil
        reload()
        container.location.current { [weak self] result in
            guard let self = self else { return }
            self.locating = false
            switch result {
            case .success(let coords):
                self.user = coords
                self.mapView.showsUserLocation = true
                self.mapView.setCamera(MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng),
                                                   fromDistance: 1_500, pitch: 0, heading: 0), animated: true)
            case .failure(.denied): self.locationMessage = L("location_denied")
            case .failure(.disabled): self.locationMessage = L("location_unsupported")
            case .failure: self.locationMessage = L("location_error")
            }
            self.reload()
        }
    }
}
