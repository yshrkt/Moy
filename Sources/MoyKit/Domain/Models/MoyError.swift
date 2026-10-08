import Foundation

public enum MoyError: Error, Equatable, Sendable {
    case invalidIdentifier(String)
    case serviceNotFound(String)
    case duplicateService(String)
    case invalidService([ServiceValidationIssue])
    case executableNotFound(String)
    case executableNotRunnable(String)
    case corruptStorage(path: String, reason: String)
    case unsupportedSchema(found: Int, supported: Int)
    case fileOperation(path: String, reason: String)
    case lockUnavailable(path: String)
    case alreadyEnabled(String)
    case notEnabled(String)
    case inconsistentState(String)
    case launchctlFailed(arguments: [String], status: Int32, message: String)
}

extension MoyError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidIdentifier(identifier):
            "Invalid service identifier '\(identifier)'. "
                + "Use 1–64 lowercase letters, digits, hyphens, or underscores; start and end with a letter or digit."
        case let .serviceNotFound(identifier):
            "Service not found: \(identifier)"
        case let .duplicateService(identifier):
            "A service with this identifier already exists: \(identifier)"
        case let .invalidService(issues):
            "Invalid service configuration: \(issues.map(\.message).joined(separator: "; "))"
        case let .executableNotFound(path):
            "Executable not found: \(path). Specify an absolute path and check the path and filename."
        case let .executableNotRunnable(path):
            "The specified file cannot be executed: \(path). Select an executable file with execute permission."
        case let .corruptStorage(path, reason):
            "Could not read service data at \(path): \(reason)"
        case let .unsupportedSchema(found, supported):
            "Unsupported service data schema \(found); this version supports schema \(supported)."
        case let .fileOperation(path, reason):
            "File operation failed at \(path): \(reason)"
        case let .lockUnavailable(path):
            "Could not lock the service data at \(path)."
        case let .alreadyEnabled(label):
            "Service is already enabled: \(label)"
        case let .notEnabled(label):
            "Service is not enabled: \(label)"
        case let .inconsistentState(label):
            "Service has an inconsistent launchd state: \(label)"
        case let .launchctlFailed(arguments, status, message):
            "launchctl \(arguments.joined(separator: " ")) failed with status \(status): \(message)"
        }
    }
}
