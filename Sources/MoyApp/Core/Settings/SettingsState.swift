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
    case launchAtLoginFailed(String)
    case cliNotBundled
    case cliDestinationExists
    case cliInstallationFailed
    case cliUninstallationFailed
    case cliLinkChanged
    case cliAuthorizationFailed(String)
    case unexpected(String)

    static func from(_ error: any Error) -> Self {
        error as? Self ?? .unexpected(error.localizedDescription)
    }
}
