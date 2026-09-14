import ArgumentParser

struct RemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Disable and remove a service definition. Log files are preserved.",
    )

    @Argument(help: "Service identifier.")
    var identifier: String

    mutating func run() async throws {
        let identifier = try CLIParsing.identifier(identifier)
        try await CLIContext.services.remove(identifier: identifier)
        print("Removed \(identifier.rawValue)")
    }
}
