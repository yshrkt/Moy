import ArgumentParser
import MoyKit

struct EditCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "edit", abstract: "Edit a service definition.")

    @Argument(help: "Service identifier.")
    var identifier: String

    @Option(name: .customLong("name"), help: "Replace the human-readable name.")
    var displayName: String?

    @Flag(name: .customLong("clear-name"), help: "Remove the human-readable name.")
    var clearDisplayName = false

    @Option(help: "Replace the service description.")
    var description: String?

    @Flag(name: .customLong("clear-description"), help: "Remove the service description.")
    var clearDescription = false

    @Option(help: "Replace the executable path.")
    var program: String?

    @Option(
        name: [.customLong("arg"), .customLong("argument")],
        parsing: .unconditionalSingleValue,
        help: "Replace program arguments. Repeat as needed.",
    )
    var arguments: [String] = []

    @Flag(name: .customLong("clear-arguments"), help: "Remove every program argument after the executable.")
    var clearArguments = false

    @Option(name: .customLong("working-directory"), help: "Replace the working directory.")
    var workingDirectory: String?

    @Flag(name: .customLong("clear-working-directory"), help: "Remove the working directory.")
    var clearWorkingDirectory = false

    @Option(
        name: [.customLong("env"), .customLong("environment")],
        help: "Replace the environment with KEY=VALUE entries.",
    )
    var environment: [String] = []

    @Flag(name: .customLong("clear-environment"), help: "Remove every environment variable.")
    var clearEnvironment = false

    @Option(name: .customLong("run-at-load"), help: "Set RunAtLoad to true or false.")
    var runAtLoad: Bool?

    @Option(name: .customLong("keep-alive"), help: "Set KeepAlive to true or false.")
    var keepAlive: Bool?

    @Option(name: .customLong("throttle-interval"), help: "Replace the launch throttle interval.")
    var throttleInterval: Int?

    @Flag(name: .customLong("clear-throttle-interval"), help: "Use launchd's default throttle interval.")
    var clearThrottleInterval = false

    @Option(name: .customLong("stdout"), help: "Replace the standard output log path.")
    var standardOutPath: String?

    @Option(name: .customLong("stderr"), help: "Replace the standard error log path.")
    var standardErrorPath: String?

    mutating func run() async throws {
        try validateOptions()
        let identifier = try CLIParsing.identifier(identifier)
        var service = try await CLIContext.services.find(identifier: identifier)
        applyMetadata(to: &service)
        applyProgram(to: &service)
        try applyEnvironmentAndBehavior(to: &service)
        applyLogs(to: &service)

        try await CLIContext.services.update(service)
        print("Updated \(identifier.rawValue)")
    }
}

private extension EditCommand {
    func applyMetadata(to service: inout ServiceDefinition) {
        if clearDisplayName {
            service.displayName = nil
        }
        if let displayName {
            service.displayName = CLIParsing.optionalText(displayName)
        }
        if clearDescription {
            service.description = nil
        }
        if let description {
            service.description = CLIParsing.optionalText(description)
        }
    }

    func applyProgram(to service: inout ServiceDefinition) {
        if let program {
            service.programArguments[0] = program
        }
        if clearArguments {
            service.programArguments = [service.programArguments[0]]
        }
        if !arguments.isEmpty {
            service.programArguments = [service.programArguments[0]] + arguments
        }
        if clearWorkingDirectory {
            service.workingDirectory = nil
        }
        if let workingDirectory {
            service.workingDirectory = CLIParsing.optionalText(workingDirectory)
        }
    }

    func applyEnvironmentAndBehavior(to service: inout ServiceDefinition) throws {
        if clearEnvironment {
            service.environmentVariables = [:]
        }
        if !environment.isEmpty {
            service.environmentVariables = try CLIParsing.environment(environment)
        }
        if let runAtLoad {
            service.runAtLoad = runAtLoad
        }
        if let keepAlive {
            service.keepAlive = keepAlive
        }
        if clearThrottleInterval {
            service.throttleInterval = nil
        }
        if let throttleInterval {
            service.throttleInterval = throttleInterval
        }
    }

    func applyLogs(to service: inout ServiceDefinition) {
        if let standardOutPath {
            service.standardOutPath = standardOutPath
        }
        if let standardErrorPath {
            service.standardErrorPath = standardErrorPath
        }
    }

    func validateOptions() throws {
        let conflicts = [
            (clearDisplayName && displayName != nil, "--name and --clear-name"),
            (clearDescription && description != nil, "--description and --clear-description"),
            (clearArguments && !arguments.isEmpty, "--argument and --clear-arguments"),
            (clearWorkingDirectory && workingDirectory != nil, "--working-directory and --clear-working-directory"),
            (clearEnvironment && !environment.isEmpty, "--environment and --clear-environment"),
            (clearThrottleInterval && throttleInterval != nil, "--throttle-interval and --clear-throttle-interval"),
        ]
        if let conflict = conflicts.first(where: { $0.0 }) {
            throw ValidationError("Options cannot be used together: \(conflict.1)")
        }
    }
}
