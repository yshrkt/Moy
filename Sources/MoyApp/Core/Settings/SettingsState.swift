import Foundation
import MoyKit
import NanoRedux
import Observation

typealias SettingsStore = Store<SettingsState, SettingsAction>

enum SettingsTab: Hashable, Sendable {
    case settings
    case information
}

enum CLIInstallationStatus: Equatable, Sendable {
    case notInstalled
    case installed
    case conflict
}

@Observable
final class SettingsState {
    var logRotationSettings: LogRotationSettings?
    var isLogRotationRegistrationUnknown = false
    var logRotationFailures: [String] = []
    var isOperatingLogRotation = false
    var selectedTab: SettingsTab = .settings
    var launchAtLoginStatus: LaunchAtLoginStatus?
    var isCheckingLaunchAtLogin = false
    var isUpdatingLaunchAtLogin = false
    var isOperatingLaunchAtLogin: Bool {
        isCheckingLaunchAtLogin || isUpdatingLaunchAtLogin
    }

    var cliStatus: CLIInstallationStatus?
    var isCheckingCLI = false
    var isInstallingCLI = false
    var isUninstallingCLI = false
    var isConfirmingCLIUninstallation = false
    var isOperatingCLI: Bool {
        isCheckingCLI || isInstallingCLI || isUninstallingCLI
    }

    var failure: SettingsFailure?
}

enum SettingsFailure: Error, Equatable, Sendable {
    case logRotationStateUnavailable(String)
    case logRotationUpdateFailed(LogRotationSettings, String)
    case logRotationFailed(String)
    case invalidLogRotationSettings
    case launchAtLoginFailed(String)
    case cliNotBundled
    case cliDestinationExists
    case cliInstallationFailed
    case cliUninstallationFailed
    case cliLinkChanged
    case cliAuthorizationFailed(String)
    case unexpected(String)

    static func from(_ error: any Error) -> Self {
        if let error = error as? Self {
            return error
        }
        if let error = error as? LogRotationError {
            if case let .jobUpdateFailed(settings, reason) = error {
                return .logRotationUpdateFailed(settings, reason)
            }
            if case let .jobStateUnavailable(reason) = error {
                return .logRotationStateUnavailable(reason)
            }
            if error == .invalidSettings {
                return .invalidLogRotationSettings
            }
            return .logRotationFailed(error.localizedDescription)
        }
        return .unexpected(error.localizedDescription)
    }
}
