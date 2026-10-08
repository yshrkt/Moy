import Foundation

public enum ServiceValidator {
    public static func validate(_ service: ServiceDefinition) throws {
        var issues: [ServiceValidationIssue] = []

        if let displayName = service.displayName,
           displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            issues.append(.blankDisplayName)
        }
        if service.programArguments.isEmpty || service.programArguments[0].isEmpty {
            issues.append(.missingExecutable)
        } else if !service.programArguments[0].hasPrefix("/") {
            issues.append(.relativeExecutable)
        }
        if let workingDirectory = service.workingDirectory,
           !workingDirectory.isEmpty,
           !workingDirectory.hasPrefix("/")
        {
            issues.append(.relativeWorkingDirectory)
        }
        if let throttleInterval = service.throttleInterval, throttleInterval < 1 {
            issues.append(.invalidThrottleInterval)
        }
        if service.standardOutPath.isEmpty || !service.standardOutPath.hasPrefix("/") {
            issues.append(.invalidStandardOutPath)
        }
        if service.standardErrorPath.isEmpty || !service.standardErrorPath.hasPrefix("/") {
            issues.append(.invalidStandardErrorPath)
        }
        if service.environmentVariables.keys.contains(where: { $0.isEmpty || $0.contains("=") }) {
            issues.append(.invalidEnvironmentName)
        }

        if !issues.isEmpty {
            throw MoyError.invalidService(issues)
        }
    }
}
