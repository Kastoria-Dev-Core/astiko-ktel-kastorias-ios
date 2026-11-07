import SwiftUI

/// The map: every stop, the chosen line along the streets, and the buses
struct MapScreen: View {
    let initialLineId: String?
    let initialStopId: String?
    let recenter: Int

    var body: some View {
        Text(L("tab_map"))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AC.background)
    }
}
