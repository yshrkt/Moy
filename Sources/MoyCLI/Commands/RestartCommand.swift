import ArgumentParser

struct RestartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "restart",
        abstract: "Start a waiting service or restart a running service.",
    )

    @Argument(help: "Service identifier.")
    var identifier: String

    mutating func run() async throws {
        let identifier = try CLIParsing.identifier(identifier)
        try await CLIContext.services.restart(identifier: identifier)
        print("Restarted \(identifier.rawValue)")
    }
}
