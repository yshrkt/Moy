import MoyKit
import NanoRedux

struct SettingsReducer: InjectableReducer {
    let dependencies: SettingsDependencies

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func reduce(into state: inout SettingsState, action: SettingsAction) -> Effect<SettingsAction> {
        switch action {
        case .refreshLaunchAtLoginStatus:
            guard !state.isOperatingLaunchAtLogin else { return .none }
            state.isCheckingLaunchAtLogin = true
            let useCase = dependencies.launchAtLoginUseCase
            return .run { await .receiveLaunchAtLoginStatus(useCase.status()) }

        case let .receiveLaunchAtLoginStatus(status):
            state.isCheckingLaunchAtLogin = false
            state.launchAtLoginStatus = status
            return .none

        case let .setLaunchAtLogin(enabled):
            return setLaunchAtLogin(enabled, into: &state)

        case let .receiveLaunchAtLoginUpdate(status, failure):
            state.isUpdatingLaunchAtLogin = false
            state.launchAtLoginStatus = status
            if let failure {
                state.failure = failure
            }
            return .none

        case .openLoginItemsSettings:
            let useCase = dependencies.launchAtLoginUseCase
            return .run {
                await useCase.openSystemSettings()
                return .refreshLaunchAtLoginStatus
            }

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

        case .requestCLIUninstallation:
            guard !state.isOperatingCLI, state.cliStatus == .installed else { return .none }
            state.isConfirmingCLIUninstallation = true
            return .none

        case .dismissCLIUninstallation:
            state.isConfirmingCLIUninstallation = false
            return .none

        case .uninstallCLI:
            guard state.isConfirmingCLIUninstallation, !state.isOperatingCLI else { return .none }
            state.isConfirmingCLIUninstallation = false
            state.isUninstallingCLI = true
            state.failure = nil
            let client = dependencies.cliInstallerClient
            return .run {
                do {
                    try await client.uninstall()
                    return .receiveCLIUninstallation(.success(()))
                } catch is CancellationError {
                    return .cancelCLIUninstallation
                } catch {
                    return .receiveCLIUninstallation(.failure(.from(error)))
                }
            }

        case .receiveCLIUninstallation(.success):
            state.isUninstallingCLI = false
            state.cliStatus = .notInstalled
            return .none

        case let .receiveCLIUninstallation(.failure(failure)):
            state.isUninstallingCLI = false
            state.failure = failure
            return .run { .refreshCLIStatus }

        case .cancelCLIUninstallation:
            state.isUninstallingCLI = false
            return .run { .refreshCLIStatus }

        case .revealCLI:
            guard !state.isOperatingCLI, state.cliStatus == .conflict else { return .none }
            let client = dependencies.workspaceClient
            return .run {
                do {
                    try await client.reveal(CLIInstaller.installationPath)
                    return .receiveCLIReveal(.success(()))
                } catch {
                    return .receiveCLIReveal(.failure(.from(error)))
                }
            }

        case .receiveCLIReveal(.success):
            return .none

        case let .receiveCLIReveal(.failure(failure)):
            state.failure = failure
            return .none

        case .dismissFailure:
            state.failure = nil
            return .none

        case .cancelCLIInstallation:
            state.isInstallingCLI = false
            return .run { .refreshCLIStatus }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool, into state: inout SettingsState) -> Effect<SettingsAction> {
        guard !state.isOperatingLaunchAtLogin, let status = state.launchAtLoginStatus else { return .none }
        let registered = status == .enabled || status == .requiresApproval
        guard enabled != registered else { return .none }
        state.isUpdatingLaunchAtLogin = true
        state.failure = nil
        let useCase = dependencies.launchAtLoginUseCase
        return .run {
            do {
                try await useCase.setEnabled(enabled)
                return await .receiveLaunchAtLoginUpdate(useCase.status(), nil)
            } catch let LaunchAtLoginError.updateFailed(message) {
                return await .receiveLaunchAtLoginUpdate(useCase.status(), .launchAtLoginFailed(message))
            } catch {
                return await .receiveLaunchAtLoginUpdate(
                    useCase.status(), .launchAtLoginFailed(error.localizedDescription),
                )
            }
        }
    }

    private func refreshCLIStatus(into state: inout SettingsState) -> Effect<SettingsAction> {
        guard !state.isOperatingCLI else { return .none }
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
        guard !state.isOperatingCLI,
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
