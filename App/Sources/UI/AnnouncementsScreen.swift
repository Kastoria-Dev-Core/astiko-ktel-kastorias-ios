import SwiftUI

/// The operator's announcements, with their posters full screen on a tap
struct AnnouncementsScreen: View {
    @EnvironmentObject private var store: AnnouncementsStore
    @Environment(\.openURL) private var openURL
    @State private var viewing: URL?

    var body: some View {
        Group {
            if let list = store.announcements {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if store.failed {
                            Text(L(list.isEmpty ? "announcements_offline_empty" : "announcements_offline"))
                                .font(.brand(14))
                                .foregroundStyle(AC.muted)
                        } else if list.isEmpty {
                            Text(L("announcements_none")).font(.brand(14)).foregroundStyle(AC.muted)
                        }
                        ForEach(list) { announcement in
                            card(announcement)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .refreshable { await store.refresh(force: true) }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AC.background)
        .navigationTitle(L("announcements"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel(L("refresh"))
            }
        }
        .task { await store.refresh() }
        .fullScreenCover(item: $viewing) { url in
            ImageViewer(url: url) { viewing = nil }
        }
    }

    private func card(_ announcement: Announcement) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: 2) {
                Text(announcement.title).font(.brand(17, .semibold))
                Text(publishedDate(announcement)).font(.brand(13)).foregroundStyle(AC.muted)
            }
            if let image = announcement.image.flatMap(URL.init(string:)) {
                Button {
                    viewing = image
                } label: {
                    AsyncImage(url: image) { phase in
                        switch phase {
                        case .success(let picture):
                            picture.resizable().scaledToFill()
                        case .failure:
                            placeholder { Text(L("image_unavailable")).font(.brand(13)).foregroundStyle(AC.muted) }
                        default:
                            placeholder { ProgressView() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 420, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("announcement_image", announcement.title))
            }
            if !announcement.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(announcement.text).font(.brand(15)).lineSpacing(4)
            }
            if let url = URL(string: announcement.url) {
                Button(L("open_website")) { openURL(url) }
                    .font(.brand(15, .semibold))
                    .foregroundStyle(AC.link)
            }
        }
    }

    private func placeholder<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack { content() }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(AC.surfaceVariant)
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
struct AnnouncementRow: View {
    /// The announcement to show
    let announcement: Announcement

    var body: some View {
        AppCard(padding: 12) {
            HStack(spacing: 12) {
                if let image = announcement.image.flatMap(URL.init(string:)) {
                    AsyncImage(url: image) { picture in
                        picture.resizable().scaledToFill()
                    } placeholder: {
                        AC.surfaceVariant
                    }
                    .frame(width: 56, height: 56, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(announcement.title).font(.brand(15, .semibold)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(publishedDate(announcement)).font(.brand(13)).foregroundStyle(AC.muted)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

extension URL: Identifiable {
    public var id: String { absoluteString }
}

/// Full-screen image with pinch to zoom, drag to pan, double tap to reset
private struct ImageViewer: View {
    let url: URL
    let onClose: () -> Void
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { picture in
                picture.resizable().scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in scale = min(max(lastScale * value, 1), 5) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale == 1 { offset = .zero; lastOffset = .zero }
                    }
                    .simultaneously(with: DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset })
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = 1
                    lastScale = 1
                    offset = .zero
                    lastOffset = .zero
                }
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.4), in: Circle())
            }
            .padding(12)
            .accessibilityLabel(L("close"))
        }
    }
}
