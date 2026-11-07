import SwiftUI

/// The bottom tabs. Each has its own navigation stack, so a screen opened from a tab stays part of it.
struct RootView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        VStack(spacing: 12) {
            Text(L("app_title")).font(.brand(22, .semibold))
            Text(L("stops_count", container.data.stops.count))
            Text(L("lines_count", container.data.lines.count))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AC.background)
    }
}
