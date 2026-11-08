import SwiftUI

/// Opened from the gear on Home: language, theme and voice, with "About this app" one level down
struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(L("language"))
                Segmented(options: [(value: "el", label: "Ελληνικά"), (value: "en", label: "English")],
                          selected: $settings.language)
                SectionTitle(L("theme")).padding(.top, 8)
                Segmented(options: [(value: ThemeMode.system, label: L("theme_system")),
                                    (value: ThemeMode.light, label: L("theme_light")),
                                    (value: ThemeMode.dark, label: L("theme_dark"))],
                          selected: $settings.theme)
                // Just the name and the switch: the stop page has its own speaker button for each stop
                AppCard {
                    Toggle(isOn: $settings.voice) {
                        Text(L("voice_title")).font(.brand(15, .medium))
                    }
                    .tint(AC.primary)
                }
                .padding(.top, 16)
                NavigationLink(value: Route.about) {
                    AppCard {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle").foregroundStyle(AC.ink2)
                            Text(L("about_app")).font(.brand(15, .medium))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(AC.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(AC.background)
        .navigationTitle(L("tab_settings"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// How to reach Αστικό ΚΤΕΛ Καστοριάς, who made the app, and the fine print
struct AboutScreen: View {
    @EnvironmentObject private var container: AppContainer
    @Environment(\.openURL) private var openURL

    private let phone = "+30 24670 83959"
    private let fax = "+30 24670 21364"
    private let email = "astikast@otenet.gr"

    var body: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 6) {
                    Image("AppMark")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(AC.offWhite)
                        .padding(14)
                        .frame(width: 64, height: 64)
                        .background(AC.lake, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text(L("app_title")).font(.brand(17, .semibold))
                    Text(L("version_label", version)).font(.brand(13)).foregroundStyle(AC.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                PlaceholderBanner(visible: container.data.meta.placeholder)
                SectionTitle(L("contact"))
                AppCard(spacing: 0) {
                    let address = L("contact_address")
                    row(L("contact_address_label"), address) {
                        let query = address.replacingOccurrences(of: "\n", with: " ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "http://maps.apple.com/?q=\(query)") { openURL(url) }
                    }
                    Rectangle().fill(AC.divider).frame(height: 1)
                    row(L("contact_phone"), phone) {
                        if let url = URL(string: "tel:" + phone.replacingOccurrences(of: " ", with: "")) { openURL(url) }
                    }
                    Rectangle().fill(AC.divider).frame(height: 1)
                    row(L("contact_fax"), fax, action: nil)
                    Rectangle().fill(AC.divider).frame(height: 1)
                    row(L("contact_email"), email) {
                        if let url = URL(string: "mailto:" + email) { openURL(url) }
                    }
                }
                SectionTitle(L("contributors"))
                AppCard(spacing: 0) {
                    let names = Strings.array("contributors")
                    ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                        if index > 0 { Rectangle().fill(AC.divider).frame(height: 1) }
                        Text(name).font(.brand(15)).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("official_app")).font(.brand(13))
                    Text(L("map_attribution")).font(.brand(12))
                    Text(L("font_attribution")).font(.brand(12))
                }
                .foregroundStyle(AC.muted)
                .padding(.horizontal, 4)
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AC.background)
        .navigationTitle(L("about_app"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(label).font(.brand(15)).foregroundStyle(AC.muted)
                Spacer(minLength: 8)
                Text(value)
                    .font(.brand(15, .medium))
                    .foregroundStyle(action == nil ? AC.onBackground : AC.link)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
