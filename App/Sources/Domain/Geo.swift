import Foundation

/// A position from the phone
struct Coords: Hashable {
    /// Latitude, WGS84
    let lat: Double
    /// Longitude, WGS84
    let lng: Double
    /// Radius in metres the real position is likely within
    let accuracy: Double
}

/// Distances and street paths on the map
enum Geo {
    /// Distance in metres between two points
    static func distanceMeters(_ aLat: Double, _ aLng: Double, _ bLat: Double, _ bLng: Double) -> Double {
        let r = 6_371_000.0
        let rad = Double.pi / 180
        let dLat = (bLat - aLat) * rad
        let dLng = (bLng - aLng) * rad
        let h = pow(sin(dLat / 2), 2) + cos(aLat * rad) * cos(bLat * rad) * pow(sin(dLng / 2), 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// The `count` stops closest to the point, closest first, each with its distance in metres
    static func nearestStops(_ stops: [Stop], lat: Double, lng: Double, count: Int) -> [(stop: Stop, meters: Double)] {
        Array(
            stops.map { (stop: $0, meters: distanceMeters(lat, lng, $0.lat, $0.lng)) }
                .sorted { $0.meters < $1.meters }
                .prefix(count)
        )
    }

    /// Decodes an encoded polyline (Google's format, 5 decimals, as OSRM returns it)
    static func decodePolyline(_ encoded: String) -> [LatLng] {
        let bytes = Array(encoded.utf8)
        var points: [LatLng] = []
        var index = 0
        var lat = 0
        var lng = 0

        func next() -> Int? {
            var result = 0
            var shift = 0
            while true {
                guard index < bytes.count else { return nil }
                let b = Int(bytes[index]) - 63
                index += 1
                result |= (b & 0x1f) << shift
                shift += 5
                if b < 0x20 { break }
            }
            return (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
        }

        while index < bytes.count {
            guard let dLat = next(), let dLng = next() else { break }
            lat += dLat
            lng += dLng
            points.append(LatLng(lat: Double(lat) / 1e5, lng: Double(lng) / 1e5))
        }
        return points
    }

    /// A distance as people say it: to the nearest 10 m under a kilometre ("250 μ."), then in km ("1,4 χλμ.")
    static func formatDistance(_ meters: Double, language: String) -> String {
        if meters < 1000 {
            let rounded = max(10, Int((meters / 10).rounded()) * 10)
            return language == "el" ? "\(rounded) μ." : "\(rounded) m"
        }
        let km = String(format: "%.1f", meters / 1000)
        return language == "el" ? "\(km.replacingOccurrences(of: ".", with: ",")) χλμ." : "\(km) km"
    }
}
