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
        HStack(spacing: 24) {
            appIcon
                .frame(width: 100, height: 100)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.App.name)
                    .font(.largeTitle.bold())
                Text(L10n.Settings.versionFormat(version, build))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    @ViewBuilder
    private var appIcon: some View {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") != nil,
           let icon = NSApplication.shared.applicationIconImage
        {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
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
