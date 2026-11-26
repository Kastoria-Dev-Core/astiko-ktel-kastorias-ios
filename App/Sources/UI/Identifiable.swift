import Foundation

// The models are shared with the iOS 12 build (Legacy/), where Identifiable doesn't exist yet (it's iOS 13+),
// so they're made Identifiable here, in the SwiftUI app only. Each already has its `id`.

extension Stop: Identifiable {}
extension Direction: Identifiable {}
extension Line: Identifiable {}
extension Departure: Identifiable {}
extension Destination: Identifiable {}
extension JourneyOption: Identifiable {}
extension BusOnMap: Identifiable {}
extension Announcement: Identifiable {}
