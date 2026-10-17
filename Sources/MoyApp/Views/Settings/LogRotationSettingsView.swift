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

            LabeledContent(L10n.Settings.logRotationSize) {
                HStack {
                    Text("\(store.state.logRotationSettings?.maximumSizeMB ?? 10) MB")
                        .monospacedDigit()
                    Stepper(L10n.Settings.logRotationSize, value: Binding(
                        get: { store.state.logRotationSettings?.maximumSizeMB ?? 10 },
                        set: { store.send(.logRotation(.setMaximumSize($0))) },
                    ), in: 1 ... 100_000)
                        .labelsHidden()
                        .disabled(isDisabled)
                }
            }

            LabeledContent(L10n.Settings.logRotationGenerations) {
                HStack {
                    Text((store.state.logRotationSettings?.generations ?? 5).formatted())
                        .monospacedDigit()
                    Stepper(L10n.Settings.logRotationGenerations, value: Binding(
                        get: { store.state.logRotationSettings?.generations ?? 5 },
                        set: { store.send(.logRotation(.setGenerations($0))) },
                    ), in: 1 ... 100)
                        .labelsHidden()
                        .disabled(isDisabled)
                }
            }

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
