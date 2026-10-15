import MoyKit

typealias L10n = MoyStrings

extension ServiceEditorIdentifierIssue {
    var localizedMessage: String {
        switch self {
        case let .invalidFormat(issue): issue.localizedMessage
        case .duplicate: L10n.Validation.Identifier.duplicate
        }
    }
}

extension ServiceIdentifierValidationIssue {
    var localizedMessage: String {
        switch self {
        case .empty: L10n.Validation.Identifier.empty
        case .tooLong: L10n.Validation.Identifier.tooLong
        case .invalidCharacters: L10n.Validation.Identifier.invalidCharacters
        case .invalidBoundary: L10n.Validation.Identifier.invalidBoundary
        }
    }
}

extension SettingsFailure {
    var localizedMessage: String {
        switch self {
        case let .logRotationStateUnavailable(message):
            "\(L10n.Settings.logRotationStateUnavailable)\n\(message)"
        case let .logRotationUpdateFailed(_, message):
            "\(L10n.Settings.logRotationUpdateFailed)\n\(message)"
        case .invalidLogRotationSettings:
            L10n.Settings.logRotationInvalidSettings
        case let .logRotationFailed(message):
            "\(L10n.Settings.logRotationFailure)\n\(message)"
        case let .launchAtLoginFailed(message):
            "\(L10n.Error.launchAtLoginFailed)\n\(message)"
        case .cliNotBundled:
            L10n.Error.cliNotBundled
        case .cliDestinationExists:
            L10n.Error.cliDestinationExists
        case .cliInstallationFailed:
            L10n.Error.cliInstallationFailed
        case .cliUninstallationFailed:
            L10n.Error.cliUninstallationFailed
        case .cliLinkChanged:
            L10n.Error.cliLinkChanged
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
        case .cancelled:
            ""
        case let .authorization(reason):
            "\(L10n.Error.authorizationFailed)\n\(reason)"
        case let .moy(error):
            error.localizedMessage
        case let .serviceJSON(.invalidDocument(reason)):
            "\(L10n.Error.invalidServiceJSON)\n\(reason)"
        case let .serviceJSON(.unsupportedSchema(found, supported)):
            "\(L10n.Error.unsupportedServiceJSON)\n\(found) / \(supported)"
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
        case .administratorRequired:
            L10n.Error.administratorRequired
        case .invalidInvokingUser:
            L10n.Error.invalidInvokingUser
        case .serviceChanged:
            L10n.Error.serviceChanged
        case .kindCannotChange:
            L10n.Error.kindCannotChange
        case let .operationFailed(reason):
            "\(L10n.Error.unexpected)\n\(reason)"
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

extension ServiceKind {
    var localizedName: String {
        switch self {
        case .launchAgent: L10n.Services.launchAgent
        case .launchDaemon: L10n.Services.launchDaemon
        }
    }
}
