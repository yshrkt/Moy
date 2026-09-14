import ArgumentParser

struct EnableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enable",
        abstract: "Create the plist and bootstrap a service.",
    )

    @Argument(help: "Service identifier.")
    var identifier: String

    mutating func run() async throws {
        let identifier = try CLIParsing.identifier(identifier)
        try await CLIContext.services.enable(identifier: identifier)
        print("Enabled \(identifier.rawValue)")
    }
}
