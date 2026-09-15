import SwiftUI

@MainActor
struct SettingsContentView: View {
    let store: SettingsStore

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.Settings.cliDescription)
                        .foregroundStyle(.secondary)
                    Text(L10n.Settings.cliAuthorizationHelp)
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
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text(L10n.Settings.cliTitle)
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.Settings.cliPathHelp)
                        .foregroundStyle(.secondary)
                    Text(verbatim: "moy --help")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    Text(L10n.Settings.cliVerifyHelp)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } header: {
                Text(L10n.Settings.cliPathTitle)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var installationControl: some View {
        if store.state.isInstallingCLI || store.state.isCheckingCLI {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(store.state.isInstallingCLI ? L10n.Settings.installingCLI : L10n.Settings.checkingCLI)
            }
        } else {
            switch store.state.cliStatus {
            case .installed:
                Label(L10n.Settings.cliInstalled, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .notInstalled:
                Button(L10n.Settings.installCLI) { store.send(.installCLI) }
            case .conflict, nil:
                Button(L10n.Common.refresh) { store.send(.refreshCLIStatus) }
            }
        }
    }
}
