import NanoRedux

struct SettingsReducer: InjectableReducer {
    let dependencies: SettingsDependencies

    func reduce(into state: inout SettingsState, action: SettingsAction) -> Effect<SettingsAction> {
        switch action {
        case .appear, .refreshCLIStatus:
            return refreshCLIStatus(into: &state)

        case let .selectTab(tab):
            state.selectedTab = tab
            return .none

        case let .receiveCLIStatus(.success(status)):
            state.isCheckingCLI = false
            state.cliStatus = status
            return .none

        case let .receiveCLIStatus(.failure(failure)):
            state.isCheckingCLI = false
            state.cliStatus = nil
            state.failure = failure
            return .none

        case .installCLI:
            return installCLI(into: &state)

        case .receiveCLIInstallation(.success):
            state.isInstallingCLI = false
            state.cliStatus = .installed
            return .none

        case let .receiveCLIInstallation(.failure(failure)):
            state.isInstallingCLI = false
            state.failure = failure
            return .run { .refreshCLIStatus }

        case .dismissFailure:
            state.failure = nil
            return .none

        case .cancelCLIInstallation:
            state.isInstallingCLI = false
            return .run { .refreshCLIStatus }
        }
    }

    private func refreshCLIStatus(into state: inout SettingsState) -> Effect<SettingsAction> {
        guard !state.isCheckingCLI, !state.isInstallingCLI else { return .none }
        state.isCheckingCLI = true
        let client = dependencies.cliInstallerClient
        return .run {
            do {
                return try await .receiveCLIStatus(.success(client.status()))
            } catch {
                return .receiveCLIStatus(.failure(.from(error)))
            }
        }
    }

    private func installCLI(into state: inout SettingsState) -> Effect<SettingsAction> {
        guard !state.isCheckingCLI, !state.isInstallingCLI,
              state.cliStatus == .notInstalled else { return .none }
        state.isInstallingCLI = true
        state.failure = nil
        let client = dependencies.cliInstallerClient
        return .run {
            do {
                try await client.install()
                return .receiveCLIInstallation(.success(()))
            } catch is CancellationError {
                return .cancelCLIInstallation
            } catch {
                return .receiveCLIInstallation(.failure(.from(error)))
            }
        }
    }
}
