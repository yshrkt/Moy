import NanoRedux

extension SettingsReducer {
    // swiftlint:disable:next cyclomatic_complexity
    func reduceCLI(into state: inout SettingsState, action: CLIAction) -> Effect<CLIAction> {
        switch action {
        case .refreshStatus:
            return refreshCLIStatus(into: &state)
        case let .receiveStatus(result):
            state.isCheckingCLI = false
            switch result {
            case let .success(status):
                state.cliStatus = status
            case let .failure(failure):
                state.cliStatus = nil
                state.failure = failure
            }
            return .none
        case .install:
            return installCLI(into: &state)
        case let .receiveInstallation(result):
            return finishInstallation(result, into: &state)
        case .cancelInstallation:
            state.isInstallingCLI = false
            return .run { .refreshStatus }
        case .requestUninstallation:
            guard !state.isOperatingCLI, state.cliStatus == .installed else { return .none }
            state.isConfirmingCLIUninstallation = true
            return .none
        case .dismissUninstallation:
            state.isConfirmingCLIUninstallation = false
            return .none
        case .uninstall:
            return uninstallCLI(into: &state)
        case let .receiveUninstallation(result):
            return finishUninstallation(result, into: &state)
        case .cancelUninstallation:
            state.isUninstallingCLI = false
            return .run { .refreshStatus }
        case .reveal:
            return revealCLI(into: &state)
        case let .receiveReveal(result):
            if case let .failure(failure) = result {
                state.failure = failure
            }
            return .none
        }
    }

    private func refreshCLIStatus(into state: inout SettingsState) -> Effect<CLIAction> {
        guard !state.isOperatingCLI else { return .none }
        state.isCheckingCLI = true
        let client = dependencies.cliInstallerClient
        return .run {
            do {
                return try await .receiveStatus(.success(client.status()))
            } catch {
                return .receiveStatus(.failure(.from(error)))
            }
        }
    }

    private func installCLI(into state: inout SettingsState) -> Effect<CLIAction> {
        guard !state.isOperatingCLI,
              state.cliStatus == .notInstalled else { return .none }
        state.isInstallingCLI = true
        state.failure = nil
        let client = dependencies.cliInstallerClient
        return .run {
            do {
                try await client.install()
                return .receiveInstallation(.success(()))
            } catch is CancellationError {
                return .cancelInstallation
            } catch {
                return .receiveInstallation(.failure(.from(error)))
            }
        }
    }

    private func finishInstallation(
        _ result: Result<Void, SettingsFailure>, into state: inout SettingsState,
    ) -> Effect<CLIAction> {
        state.isInstallingCLI = false
        switch result {
        case .success:
            state.cliStatus = .installed
            return .none
        case let .failure(failure):
            state.failure = failure
            return .run { .refreshStatus }
        }
    }

    private func finishUninstallation(
        _ result: Result<Void, SettingsFailure>, into state: inout SettingsState,
    ) -> Effect<CLIAction> {
        state.isUninstallingCLI = false
        switch result {
        case .success:
            state.cliStatus = .notInstalled
            return .none
        case let .failure(failure):
            state.failure = failure
            return .run { .refreshStatus }
        }
    }

    private func uninstallCLI(into state: inout SettingsState) -> Effect<CLIAction> {
        guard state.isConfirmingCLIUninstallation, !state.isOperatingCLI else { return .none }
        state.isConfirmingCLIUninstallation = false
        state.isUninstallingCLI = true
        state.failure = nil
        let client = dependencies.cliInstallerClient
        return .run {
            do {
                try await client.uninstall()
                return .receiveUninstallation(.success(()))
            } catch is CancellationError {
                return .cancelUninstallation
            } catch {
                return .receiveUninstallation(.failure(.from(error)))
            }
        }
    }

    private func revealCLI(into state: inout SettingsState) -> Effect<CLIAction> {
        guard !state.isOperatingCLI, state.cliStatus == .conflict else { return .none }
        let client = dependencies.workspaceClient
        return .run {
            do {
                try await client.reveal(CLIInstaller.installationPath)
                return .receiveReveal(.success(()))
            } catch {
                return .receiveReveal(.failure(.from(error)))
            }
        }
    }
}
