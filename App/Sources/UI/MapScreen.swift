import MapKit
import SwiftUI

/// Where the map opens: the Αφετηρία (terminal) stop, id 16001
private let terminal = CLLocationCoordinate2D(latitude: 40.52140470548326, longitude: 21.26186932879127)
/// How far the camera is from the ground when it opens on the terminal or the user: the streets around
private let townDistance: CLLocationDistance = 1_100
/// Further out than this, the stops are dots and the buses small
private let farDistance: CLLocationDistance = 6_000
/// How far past the outermost stops the map can be panned, in degrees (about 8 km)
private let areaMargin = 0.07
/// How often the buses move
private let busRefresh: UInt64 = 5_000_000_000

extension LatLng {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// The map: every stop, the chosen line along the streets, and the buses, real or estimated.
/// `initialLineId` shows just that line, `initialStopId` opens that stop's card. `recenter` goes up each time
/// the Map tab is tapped: the map then goes back to all stops, on the user or the terminal.
struct MapScreen: View {
    let initialLineId: String?
    let initialStopId: String?
    let recenter: Int

    @EnvironmentObject private var container: AppContainer
    @State private var lineFilter: String?
    @State private var openStopId: String?
    @State private var position: MapCameraPosition
    @State private var far = false
    @State private var buses: [BusOnMap] = []
    @State private var user: Coords?
    @State private var locating = false
    @State private var locationMessage: String?
    @State private var handledRecenter = -1

    init(initialLineId: String?, initialStopId: String?, recenter: Int) {
        self.initialLineId = initialLineId
        self.initialStopId = initialStopId
        self.recenter = recenter
        _lineFilter = State(initialValue: initialLineId)
        _openStopId = State(initialValue: initialStopId)
        _position = State(initialValue: .camera(MapCamera(centerCoordinate: terminal, distance: townDistance)))
    }

    /// The map tab itself, rather than a map opened from a stop or a line
    private var isTab: Bool { initialLineId == nil && initialStopId == nil }

    var body: some View {
        let data = container.data
        let selectedLine = data.line(lineFilter)
        let shownStops = shownStops(selectedLine)
        VStack(spacing: 0) {
            LineFilters(lines: data.lines, selected: $lineFilter)
            ZStack {
                map(selectedLine, shownStops)
                overlays(selectedLine)
            }
        }
        .background(AC.background)
        .toolbar(isTab ? .hidden : .visible, for: .navigationBar)
        .navigationTitle(L("tab_map"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if let stop = data.stop(initialStopId) { focus(stop) } else if let line = selectedLine { fit(line) } }
        .onChange(of: lineFilter) { _, id in
            if let line = data.line(id) {
                fit(line)
                // Don't keep a card open for a stop the line filter just hid
                if let open = openStopId, !data.lineStopIds(line).contains(open) { openStopId = nil }
            } else {
                withAnimation { position = .camera(MapCamera(centerCoordinate: home, distance: townDistance)) }
            }
        }
        .onChange(of: recenter, initial: true) { _, tap in tabTapped(tap) }
        .task(id: lineFilter) {
            while !Task.isCancelled {
                let live = await container.liveBuses.buses()
                let all = busesOnMap(data: data, estimated: container.busEstimator.estimate(.now), live: live)
                buses = all.filter { lineFilter == nil || $0.line.id == lineFilter }
                try? await Task.sleep(nanoseconds: busRefresh)
            }
        }
    }

    // MARK: - The map

    private func map(_ selectedLine: Line?, _ shownStops: [Stop]) -> some View {
        Map(position: $position, bounds: bounds) {
            if let line = selectedLine {
                // Both directions: outbound and return often take different streets
                ForEach(paths(line).indices, id: \.self) { index in
                    MapPolyline(coordinates: paths(line)[index])
                        .stroke(Color(hexString: line.color), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            ForEach(shownStops) { stop in
                Annotation(stop.title, coordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng), anchor: .center) {
                    StopPin(open: stop.id == openStopId, far: far && selectedLine == nil)
                        .onTapGesture { withAnimation(.snappy) { openStopId = stop.id } }
                }
                .annotationTitles(.hidden)
            }
            ForEach(buses) { bus in
                Annotation("\(bus.line.number) → \(bus.direction.headsign.text)",
                           coordinate: CLLocationCoordinate2D(latitude: bus.lat, longitude: bus.lng), anchor: .center) {
                    NavigationLink(value: Route.line(bus.line.id, bus.direction.id)) {
                        BusPin(line: bus.line, small: far)
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            far = context.camera.distance > farDistance
        }
    }

    @ViewBuilder
    private func overlays(_ selectedLine: Line?) -> some View {
        VStack(spacing: 0) {
            // Top left: a way into the chosen line's timetable, and whether the buses are real or estimated
            HStack(spacing: 8) {
                if let line = selectedLine {
                    NavigationLink(value: Route.line(line.id, nil)) {
                        Text(L("line_timetable") + " ›")
                            .font(.brand(12, .semibold))
                            .foregroundStyle(AC.link)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AC.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(AC.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                if !buses.isEmpty {
                    Text(L(buses.allSatisfy(\.live) ? "buses_live_short" : "buses_estimated_short"))
                        .font(.brand(12))
                        .foregroundStyle(AC.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AC.surface.opacity(0.92), in: Capsule())
                        .overlay(Capsule().strokeBorder(AC.border, lineWidth: 1))
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            Spacer()
            if let stop = container.data.stop(openStopId) {
                StopSheet(stop: stop) { withAnimation(.snappy) { openStopId = nil } }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    if let message = locationMessage {
                        Text(message)
                            .font(.brand(14))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AC.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AC.border, lineWidth: 1))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    } else {
                        Spacer()
                    }
                    // Bottom right, where the thumb is
                    Button(action: locate) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(locating ? AC.muted : AC.primary)
                            .frame(width: 56, height: 56)
                            .background(AC.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(AC.border, lineWidth: 1))
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                    }
                    .disabled(locating)
                    .accessibilityLabel(L("my_location"))
                }
                .padding(16)
            }
        }
    }

    // MARK: - What's shown

    private func shownStops(_ line: Line?) -> [Stop] {
        guard let line else { return container.data.stops }
        let ids = container.data.lineStopIds(line)
        return container.data.stops.filter { ids.contains($0.id) }
    }

    private func paths(_ line: Line) -> [[CLLocationCoordinate2D]] {
        let data = container.data
        return line.directions.flatMap { d in
            [data.directionPath(line, d.id)] + data.branchPaths(line, d.id)
        }
        .map { $0.map(\.coordinate) }
    }

    /// The network plus a margin: the map can't be panned outside it
    private var bounds: MapCameraBounds {
        let stops = container.data.stops
        let lats = stops.map(\.lat)
        let lngs = stops.map(\.lng)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else {
            return MapCameraBounds(minimumDistance: 150, maximumDistance: 80_000)
        }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: maxLat - minLat + 2 * areaMargin, longitudeDelta: maxLng - minLng + 2 * areaMargin)
        )
        return MapCameraBounds(centerCoordinateBounds: region, minimumDistance: 150, maximumDistance: 80_000)
    }

    /// The user's position when it's somewhere the map can show, otherwise the terminal
    private var home: CLLocationCoordinate2D {
        guard let user else { return terminal }
        let coordinate = CLLocationCoordinate2D(latitude: user.lat, longitude: user.lng)
        let nearest = container.data.stops.map { Geo.distanceMeters(user.lat, user.lng, $0.lat, $0.lng) }.min() ?? .infinity
        return nearest < 8_000 ? coordinate : terminal
    }

    // MARK: - Camera

    private func focus(_ stop: Stop) {
        position = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: stop.lat, longitude: stop.lng), distance: 1_500))
    }

    /// Both directions of a line, with some room around them
    private func fit(_ line: Line) {
        let points = line.directions.flatMap { container.data.directionStops(line, $0.id) }
        guard let minLat = points.map(\.lat).min(), let maxLat = points.map(\.lat).max(),
              let minLng = points.map(\.lng).min(), let maxLng = points.map(\.lng).max() else { return }
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(latitudeDelta: max(0.006, (maxLat - minLat) * 1.35), longitudeDelta: max(0.006, (maxLng - minLng) * 1.35))
        )
        withAnimation { position = .region(region) }
    }

    /// Each tap on the Map tab: all stops, zoomed on the user, asking for location the first time if needed.
    /// Without it, with location off or with no fix, it stays on the terminal.
    private func tabTapped(_ tap: Int) {
        guard isTab, tap != handledRecenter else { return }
        handledRecenter = tap
        lineFilter = nil
        openStopId = nil
        locationMessage = nil
        withAnimation { position = .camera(MapCamera(centerCoordinate: home, distance: townDistance)) }
        guard !container.location.isDenied else { return }
        Task {
            guard let coords = try? await container.location.current() else { return }
            user = coords
            // Only if still on all lines: picking a line while waiting for the fix wins
            if lineFilter == nil {
                withAnimation { position = .camera(MapCamera(centerCoordinate: home, distance: townDistance)) }
            }
        }
    }

    /// The location button: to the user, or a message saying why not
    private func locate() {
        locating = true
        locationMessage = nil
        Task {
            defer { locating = false }
            do {
                let coords = try await container.location.current()
                user = coords
                withAnimation {
                    position = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: coords.lat, longitude: coords.lng), distance: 1_500))
                }
            } catch LocationError.denied {
                locationMessage = L("location_denied")
            } catch LocationError.disabled {
                locationMessage = L("location_unsupported")
            } catch {
                locationMessage = L("location_error")
            }
        }
    }
}

// MARK: - Pins

/// A stop: a dot from far away, a pin with a bus from close by, the open one bigger and yellow
private struct StopPin: View {
    let open: Bool
    let far: Bool

    var body: some View {
        if open {
            pin(size: 30, fill: AC.routeYellow, glyph: Color(uiColor: UIColor(hex: 0x10212B)))
        } else if far {
            Circle()
                .fill(AC.lake)
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.25))
                .frame(width: 8, height: 8)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        } else {
            pin(size: 22, fill: AC.lake, glyph: .white)
        }
    }

    private func pin(size: CGFloat, fill: Color, glyph: Color) -> some View {
        Image(systemName: "bus.fill")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(glyph)
            .frame(width: size, height: size)
            .background(fill, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .frame(width: max(size, 32), height: max(size, 32))
            .contentShape(Rectangle())
    }
}

/// A bus: a white disc ringed in the line's colour, with a bus and the line number in that colour.
/// From far away just the number on the line's colour.
private struct BusPin: View {
    let line: Line
    let small: Bool

    var body: some View {
        let color = Color(hexString: line.color)
        let number = line.number.count < 2 ? "0" + line.number : line.number
        if small {
            Text(number)
                .font(.brand(10, .bold))
                .foregroundStyle(Color(hexString: line.textColor))
                .frame(width: 22, height: 22)
                .background(color, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
        } else {
            VStack(spacing: -1) {
                Image(systemName: "bus.fill").font(.system(size: 11, weight: .bold))
                Text(number).font(.brand(11, .bold))
            }
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(.white, in: Circle())
            .overlay(Circle().strokeBorder(color, lineWidth: 2.5))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1).padding(-1.5))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
    }
}

// MARK: - Line filters

/// The line badges above the map: tap one to show just that line, tap it again to go back to all stops.
/// The list button swaps the badges for the lines' names.
private struct LineFilters: View {
    let lines: [Line]
    @Binding var selected: String?
    @State private var showNames = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(lines) { line in
                            item(line).id(line.id)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 20)
                    .padding(.vertical, 8)
                }
                .onAppear { if let selected { reader.scrollTo(selected, anchor: .center) } }
            }
            .overlay(alignment: .trailing) {
                // Fades out before the list button, so a badge cut in half reads as "more this way"
                LinearGradient(colors: [AC.background.opacity(0), AC.background], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 24)
                    .allowsHitTesting(false)
            }
            Button {
                showNames.toggle()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(showNames ? AC.background : AC.onBackground)
                    .frame(width: 40, height: 40)
                    .background(showNames ? AC.onBackground : AC.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(showNames ? AC.onBackground : AC.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .accessibilityLabel(L(showNames ? "view_numbers" : "view_names"))
        }
        .background(AC.background)
    }

    @ViewBuilder
    private func item(_ line: Line) -> some View {
        let on = selected == line.id
        let color = Color(hexString: line.color)
        Button {
            selected = on ? nil : line.id
        } label: {
            if showNames {
                HStack(spacing: 6) {
                    Text(line.number.count < 2 ? "0" + line.number : line.number)
                        .font(.brand(14, .bold))
                        .foregroundStyle(on ? Color(hexString: line.textColor) : color)
                    Text(line.name.text)
                        .font(.brand(14, .medium))
                        .foregroundStyle(on ? Color(hexString: line.textColor) : AC.onBackground)
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(on ? color : AC.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? color : AC.border, lineWidth: 1))
            } else {
                // Just the badge; the chosen one gets a short bar underneath, like a tab, and the others step back
                VStack(spacing: 4) {
                    LineBadge(line: line, size: .md)
                    RoundedRectangle(cornerRadius: 2).fill(on ? color : .clear).frame(width: 20, height: 3)
                }
                .padding(.horizontal, 4)
                .padding(.top, 7)
                .opacity(selected == nil || on ? 1 : 0.45)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Stop card

/// The card of a tapped stop: its next buses, all departures, and walking directions
private struct StopSheet: View {
    let stop: Stop
    let onClose: () -> Void
    @EnvironmentObject private var container: AppContainer
    @Environment(\.openURL) private var openURL

    var body: some View {
        Ticking { now in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.title).font(.brand(18, .semibold))
                        Text(L("stop_code", stop.id)).font(.brand(13)).foregroundStyle(AC.muted)
                    }
                    .padding(.top, 6)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(AC.ink2).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L("close"))
                }
                DepartureList(departures: container.schedule.nextDepartures(stop.id, now: now, limit: 3, live: container.liveTrips), now: now)
                HStack(spacing: 8) {
                    NavigationLink(value: Route.stop(stop.id)) {
                        Text(L("all_departures"))
                            .font(.brand(15, .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(AC.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        // Walking directions in Apple Maps
                        if let url = URL(string: "http://maps.apple.com/?daddr=\(stop.lat),\(stop.lng)&dirflg=w") { openURL(url) }
                    } label: {
                        Label(L("directions"), systemImage: "figure.walk")
                            .font(.brand(15, .semibold))
                            .foregroundStyle(AC.primary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AC.outline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 12)
            .background(AC.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(AC.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
    }
}
