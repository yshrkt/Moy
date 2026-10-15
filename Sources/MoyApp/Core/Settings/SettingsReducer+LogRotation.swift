import MoyKit
import NanoRedux

extension SettingsReducer {
    func reduceLogRotation(into state: inout SettingsState, action: LogRotationAction) -> Effect<SettingsAction> {
        switch action {
        case let .receive(result):
            state.isOperatingLogRotation = false
            receiveLogRotation(result, into: &state)
            return .none
        case .refresh:
            return operateLogRotation(into: &state, settings: nil)
        case let .setEnabled(enabled):
            guard !state.isLogRotationRegistrationUnknown,
                  var settings = state.logRotationSettings else { return .none }
            settings.isEnabled = enabled
            return operateLogRotation(into: &state, settings: settings)
        case let .setMaximumSize(size):
            guard !state.isLogRotationRegistrationUnknown,
                  var settings = state.logRotationSettings else { return .none }
            settings.maximumSizeMB = size
            return operateLogRotation(into: &state, settings: settings)
        case let .setGenerations(count):
            guard !state.isLogRotationRegistrationUnknown,
                  var settings = state.logRotationSettings else { return .none }
            settings.generations = count
            return operateLogRotation(into: &state, settings: settings)
        }
    }

    private func receiveLogRotation(
        _ result: Result<LogRotationStatus, SettingsFailure>, into state: inout SettingsState,
    ) {
        switch result {
        case let .success(status):
            state.isLogRotationRegistrationUnknown = false
            state.logRotationSettings = status.settings
            state.logRotationFailures = status.failures
        case let .failure(failure):
            state.failure = failure
            if case let .logRotationUpdateFailed(settings, _) = failure {
                state.isLogRotationRegistrationUnknown = false
                state.logRotationSettings = settings
            } else if case .logRotationStateUnavailable = failure {
                state.isLogRotationRegistrationUnknown = true
            }
        }
    }

    private func operateLogRotation(
        into state: inout SettingsState, settings: LogRotationSettings?,
    ) -> Effect<SettingsAction> {
        guard !state.isOperatingLogRotation else { return .none }
        state.isOperatingLogRotation = true
        let useCase = dependencies.logRotationUseCase
        return .run {
            do {
                let status: LogRotationStatus = if let settings {
                    try await useCase.update(settings)
                } else {
                    try await useCase.refresh()
                }
                return .logRotation(.receive(.success(status)))
            } catch {
                return .logRotation(.receive(.failure(.from(error))))
            }
        }
    }
}
