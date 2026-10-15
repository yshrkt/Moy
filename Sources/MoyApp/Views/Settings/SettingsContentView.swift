import SwiftUI

@MainActor
struct SettingsContentView: View {
    let store: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle(L10n.Settings.launchAtLoginTitle, isOn: Binding(
                    get: {
                        store.state.launchAtLoginStatus == .enabled
                            || store.state.launchAtLoginStatus == .requiresApproval
                    },
                    set: { store.send(.setLaunchAtLogin($0)) },
                ))
                .toggleStyle(.switch)
                .disabled(store.state.isOperatingLaunchAtLogin || store.state.launchAtLoginStatus == nil)

                Text(L10n.Settings.launchAtLoginDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if store.state.isOperatingLaunchAtLogin {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(L10n.Settings.launchAtLoginUpdating)
                }
                if store.state.launchAtLoginStatus == .requiresApproval {
                    Text(L10n.Settings.launchAtLoginApproval)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button(L10n.Settings.openLoginItemsSettings) { store.send(.openLoginItemsSettings) }
                }
            } header: {
                Text(L10n.Settings.generalTitle)
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Settings.cliDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(L10n.Settings.cliCommand)
                        Spacer()
                        installationControl
                    }

                    Divider()

                    LabeledContent(L10n.Settings.cliDestination) {
                        Text(verbatim: CLIInstaller.installationPath)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                    }

                    if store.state.cliStatus == .conflict {
                        Label(L10n.Settings.cliConflict, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text(L10n.Settings.cliTitle)
            }

            LogRotationSettingsView(store: store)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .scrollEdgeEffectHidden(true, for: .top)
    }

    private var progressMessage: String {
        if store.state.isInstallingCLI {
            return L10n.Settings.installingCLI
        }
        if store.state.isUninstallingCLI {
            return L10n.Settings.uninstallingCLI
        }
        return L10n.Settings.checkingCLI
    }

    @ViewBuilder
    private var installationControl: some View {
        if store.state.isOperatingCLI {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(progressMessage)
            }
        } else {
            switch store.state.cliStatus {
            case .installed:
                Label(L10n.Settings.cliInstalled, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button(L10n.Settings.uninstallCLI) { store.send(.requestCLIUninstallation) }
            case .notInstalled:
                Button(L10n.Settings.installCLI) { store.send(.installCLI) }
            case .conflict:
                Button(L10n.Common.reveal) { store.send(.revealCLI) }
            case nil:
                Button(L10n.Common.refresh) { store.send(.refreshCLIStatus) }
            }
        }
    }
}
