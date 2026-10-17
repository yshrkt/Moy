import MoyKit
import NanoRedux

extension SettingsReducer {
    func reduceLaunchAtLogin(
        into state: inout SettingsState, action: LaunchAtLoginAction,
    ) -> Effect<LaunchAtLoginAction> {
        switch action {
        case .refreshStatus:
            guard !state.isOperatingLaunchAtLogin else { return .none }
            state.isCheckingLaunchAtLogin = true
            let useCase = dependencies.launchAtLoginUseCase
            return .run { await .receiveStatus(useCase.status()) }

        case let .receiveStatus(status):
            state.isCheckingLaunchAtLogin = false
            state.launchAtLoginStatus = status
            return .none

        case let .setEnabled(enabled):
            return setLaunchAtLogin(enabled, into: &state)

        case let .receiveUpdate(status, failure):
            state.isUpdatingLaunchAtLogin = false
            state.launchAtLoginStatus = status
            if let failure {
                state.failure = failure
            }
            return .none

        case .openSystemSettings:
            let useCase = dependencies.launchAtLoginUseCase
            return .run {
                await useCase.openSystemSettings()
                return .refreshStatus
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool, into state: inout SettingsState) -> Effect<LaunchAtLoginAction> {
        guard !state.isOperatingLaunchAtLogin, let status = state.launchAtLoginStatus else { return .none }
        let registered = status == .enabled || status == .requiresApproval
        guard enabled != registered else { return .none }
        state.isUpdatingLaunchAtLogin = true
        state.failure = nil
        let useCase = dependencies.launchAtLoginUseCase
        return .run {
            do {
                try await useCase.setEnabled(enabled)
                return await .receiveUpdate(useCase.status(), nil)
            } catch let LaunchAtLoginError.updateFailed(message) {
                return await .receiveUpdate(useCase.status(), .launchAtLoginFailed(message))
            } catch {
                return await .receiveUpdate(
                    useCase.status(), .launchAtLoginFailed(error.localizedDescription),
                )
            }
        }
    }
}
