import ArgumentParser
import MoyKit

struct AddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add a service definition.")

    @Option(help: "Unique Moy identifier using lowercase letters, digits, hyphens, or underscores.")
    var identifier: String

    @Option(name: .customLong("name"), help: "Human-readable service name.")
    var displayName: String?

    @Option(help: "Short service description.")
    var description: String?

    @Option(help: "Absolute path to the executable.")
    var program: String

    @Option(
        name: [.customLong("arg"), .customLong("argument")],
        parsing: .unconditionalSingleValue,
        help: "Program argument. Repeat for multiple arguments.",
    )
    var arguments: [String] = []

    @Option(name: .customLong("working-directory"), help: "Absolute working directory path.")
    var workingDirectory: String?

    @Option(
        name: [.customLong("env"), .customLong("environment")],
        help: "Environment variable in KEY=VALUE form. Repeat as needed.",
    )
    var environment: [String] = []

    @Flag(name: .customLong("run-at-load"), help: "Run when the LaunchAgent is loaded.")
    var runAtLoad = false

    @Flag(name: .customLong("keep-alive"), help: "Keep the service running.")
    var keepAlive = false

    @Option(name: .customLong("throttle-interval"), help: "Minimum number of seconds between launches.")
    var throttleInterval: Int?

    @Option(name: .customLong("stdout"), help: "Absolute standard output log path.")
    var standardOutPath: String?

    @Option(name: .customLong("stderr"), help: "Absolute standard error log path.")
    var standardErrorPath: String?

    @Flag(help: "Enable the service after saving it.")
    var enable = false

    mutating func run() async throws {
        let created = try await CLIContext.services.create(
            ServiceDraft(
                identifier: CLIParsing.identifier(identifier),
                displayName: CLIParsing.optionalText(displayName),
                description: CLIParsing.optionalText(description),
                programArguments: [program] + arguments,
                workingDirectory: CLIParsing.optionalText(workingDirectory),
                environmentVariables: CLIParsing.environment(environment),
                runAtLoad: runAtLoad,
                keepAlive: keepAlive,
                throttleInterval: throttleInterval,
                standardOutPath: CLIParsing.optionalText(standardOutPath),
                standardErrorPath: CLIParsing.optionalText(standardErrorPath),
            ),
            enable: enable,
        )
        print("Added \(created.identifier.rawValue)\(enable ? " and enabled it" : "")")
    }
}
