import MoyKit

typealias L10n = MoyStrings

extension SettingsFailure {
    var localizedMessage: String {
        switch self {
        case .cliNotBundled:
            L10n.Error.cliNotBundled
        case .cliDestinationExists:
            L10n.Error.cliDestinationExists
        case .cliInstallationFailed:
            L10n.Error.cliInstallationFailed
        case let .cliAuthorizationFailed(message):
            "\(L10n.Error.cliAuthorizationFailed)\n\(message)"
        case let .unexpected(message):
            "\(L10n.Error.unexpected)\n\(message)"
        }
    }
}

extension ServicesFailure {
    var localizedMessage: String {
        switch self {
        case let .moy(error):
            error.localizedMessage
        case .invalidThrottleInterval:
            L10n.Error.invalidThrottle
        case .emptyEnvironmentKey:
            L10n.Error.emptyEnvironmentKey
        case let .duplicateEnvironmentKey(key):
            "\(L10n.Error.duplicateEnvironmentKey) \(key)"
        case let .fileNotFound(path):
            "\(L10n.Error.fileNotFound)\n\(path)"
        case let .unexpected(message):
            "\(L10n.Error.unexpected)\n\(message)"
        }
    }
}

private extension MoyError {
    var localizedMessage: String {
        switch self {
        case let .invalidIdentifier(identifier):
            "\(L10n.Error.invalidIdentifier)\n\(identifier)"
        case let .serviceNotFound(identifier):
            "\(L10n.Error.serviceNotFound)\n\(identifier)"
        case let .duplicateService(identifier):
            "\(L10n.Error.duplicateService)\n\(identifier)"
        case let .invalidService(issues):
            "\(L10n.Error.invalidService)\n\(issues.map(\.localizedMessage).joined(separator: "\n"))"
        case let .executableNotFound(path):
            "\(L10n.Error.executableNotFound)\n\(path)"
        case let .executableNotRunnable(path):
            "\(L10n.Error.executableNotRunnable)\n\(path)"
        case let .corruptStorage(path, reason):
            "\(L10n.Error.corruptStorage)\n\(path)\n\(reason)"
        case let .unsupportedSchema(found, supported):
            "\(L10n.Error.unsupportedSchema)\n\(found) / \(supported)"
        case let .fileOperation(path, reason):
            "\(L10n.Error.fileOperation)\n\(path)\n\(reason)"
        case let .lockUnavailable(path):
            "\(L10n.Error.lockUnavailable)\n\(path)"
        case let .alreadyEnabled(label):
            "\(L10n.Error.alreadyEnabled)\n\(label)"
        case let .notEnabled(label):
            "\(L10n.Error.notEnabled)\n\(label)"
        case let .inconsistentState(label):
            "\(L10n.Error.inconsistentState)\n\(label)"
        case let .serviceUpdateNotApplied(identifier, reason):
            "\(L10n.Error.serviceUpdateNotApplied)\n\(identifier)\n\(reason)"
        case let .launchctlFailed(arguments, status, message):
            "\(L10n.Error.launchctlFailed)\nlaunchctl \(arguments.joined(separator: " "))\n\(status): \(message)"
        }
    }
}

extension ServiceValidationIssue {
    var localizedMessage: String {
        switch self {
        case .blankDisplayName:
            L10n.Validation.blankDisplayName
        case .missingExecutable:
            L10n.Validation.missingExecutable
        case .relativeExecutable:
            L10n.Validation.relativeExecutable
        case .relativeWorkingDirectory:
            L10n.Validation.relativeWorkingDirectory
        case .invalidThrottleInterval:
            L10n.Validation.invalidThrottleInterval
        case .invalidStandardOutPath:
            L10n.Validation.invalidStandardOutPath
        case .invalidStandardErrorPath:
            L10n.Validation.invalidStandardErrorPath
        case .invalidEnvironmentName:
            L10n.Validation.invalidEnvironmentName
        }
    }
}
