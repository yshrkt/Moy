import ArgumentParser

struct DisableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disable",
        abstract: "Boot out a service and remove its plist.",
    )

    @Argument(help: "Service identifier.")
    var identifier: String

    mutating func run() async throws {
        let identifier = try CLIParsing.identifier(identifier)
        try await CLIContext.services.disable(identifier: identifier)
        print("Disabled \(identifier.rawValue)")
    }
}
