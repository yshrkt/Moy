import MoyKit
import SwiftUI

@MainActor
struct LogRotationSettingsView: View {
    let store: SettingsStore

    var body: some View {
        Section {
            Toggle(L10n.Settings.logRotationEnabled, isOn: Binding(
                get: { store.state.logRotationSettings?.isEnabled ?? false },
                set: { store.send(.logRotation(.setEnabled($0))) },
            ))
            .toggleStyle(.switch)
            .disabled(isDisabled)

            Stepper(value: Binding(
                get: { store.state.logRotationSettings?.maximumSizeMB ?? 10 },
                set: { store.send(.logRotation(.setMaximumSize($0))) },
            ), in: 1 ... 100_000) {
                LabeledContent(L10n.Settings.logRotationSize) {
                    Text("\(store.state.logRotationSettings?.maximumSizeMB ?? 10) MB")
                        .monospacedDigit()
                }
            }
            .disabled(isDisabled)

            Stepper(value: Binding(
                get: { store.state.logRotationSettings?.generations ?? 5 },
                set: { store.send(.logRotation(.setGenerations($0))) },
            ), in: 1 ... 100) {
                LabeledContent(L10n.Settings.logRotationGenerations) {
                    Text((store.state.logRotationSettings?.generations ?? 5).formatted())
                        .monospacedDigit()
                }
            }
            .disabled(isDisabled)

            Text(L10n.Settings.logRotationDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
            if !store.state.logRotationFailures.isEmpty {
                Text(L10n.Settings.logRotationFailure)
                    .foregroundStyle(.red)
                Text(store.state.logRotationFailures.joined(separator: "\n"))
                    .font(.caption)
                    .textSelection(.enabled)
            }
        } header: {
            Text(L10n.Settings.logRotationTitle)
        }
    }

    private var isDisabled: Bool {
        store.state.logRotationSettings == nil
            || store.state.isLogRotationRegistrationUnknown
    }
}
