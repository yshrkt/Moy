import AppKit
import SwiftUI

struct SettingsInformationView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            appIcon
                .frame(width: 100, height: 100)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.App.name)
                    .font(.system(size: 24, weight: .bold))
                Text(L10n.Settings.versionFormat(version, build))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer(minLength: 12)
                if let repositoryURL = URL(string: "https://github.com/yshrkt/Moy") {
                    Link(destination: repositoryURL) {
                        HStack(spacing: 6) {
                            Image("github_mark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 16, height: 16)
                                .accessibilityHidden(true)
                            Text(L10n.Settings.repository)
                        }
                    }
                    .accessibilityLabel(L10n.Settings.openRepository)
                    .help(L10n.Settings.openRepository)
                }
            }
            .padding(.vertical, 8)
            .frame(height: 100)
        }
        .offset(y: -24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .overlay(alignment: .bottom) {
            Text(L10n.Settings.copyright)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") != nil,
           let icon = NSApplication.shared.applicationIconImage
        {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                // macOS app icons include a 10% inset around the visible artwork.
                // Keep that inset outside the layout bounds so the artwork aligns with the link.
                .frame(width: 110, height: 110)
                .padding(-15)
        } else {
            Image(systemName: "terminal")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview {
        SettingsInformationView()
            .frame(width: 560, height: 440)
    }
#endif
