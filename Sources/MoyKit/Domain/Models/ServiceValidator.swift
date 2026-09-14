import Foundation

public enum ServiceValidator {
    public static func validate(_ service: ServiceDefinition) throws {
        var messages: [String] = []

        if let displayName = service.displayName,
           displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            messages.append("Display name must not be blank when provided")
        }
        if service.programArguments.isEmpty || service.programArguments[0].isEmpty {
            messages.append("ProgramArguments must start with an executable path")
        } else if !service.programArguments[0].hasPrefix("/") {
            messages.append("The executable path must be absolute")
        }
        if let workingDirectory = service.workingDirectory,
           !workingDirectory.isEmpty,
           !workingDirectory.hasPrefix("/")
        {
            messages.append("WorkingDirectory must be an absolute path")
        }
        if let throttleInterval = service.throttleInterval, throttleInterval < 1 {
            messages.append("ThrottleInterval must be at least 1 second")
        }
        if service.standardOutPath.isEmpty || !service.standardOutPath.hasPrefix("/") {
            messages.append("StandardOutPath must be an absolute path")
        }
        if service.standardErrorPath.isEmpty || !service.standardErrorPath.hasPrefix("/") {
            messages.append("StandardErrorPath must be an absolute path")
        }
        if service.environmentVariables.keys.contains(where: { $0.isEmpty || $0.contains("=") }) {
            messages.append("Environment variable names must be non-empty and must not contain '='")
        }

        if !messages.isEmpty {
            throw MoyError.invalidService(messages)
        }
    }
}
