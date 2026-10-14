/// Validation reasons shared by the GUI and CLI, independent of the display language.
public enum ServiceValidationIssue: String, Codable, CaseIterable, Equatable, Sendable {
    case blankDisplayName
    case missingExecutable
    case relativeExecutable
    case relativeWorkingDirectory
    case invalidThrottleInterval
    case invalidStandardOutPath
    case invalidStandardErrorPath
    case invalidEnvironmentName

    var message: String {
        switch self {
        case .blankDisplayName:
            "Display name must not be blank when provided"
        case .missingExecutable:
            "ProgramArguments must start with an executable path"
        case .relativeExecutable:
            "The executable path must be absolute"
        case .relativeWorkingDirectory:
            "WorkingDirectory must be an absolute path"
        case .invalidThrottleInterval:
            "ThrottleInterval must be at least 1 second"
        case .invalidStandardOutPath:
            "StandardOutPath must be an absolute path"
        case .invalidStandardErrorPath:
            "StandardErrorPath must be an absolute path"
        case .invalidEnvironmentName:
            "Environment variable names must be non-empty and must not contain '='"
        }
    }
}
