import ArgumentParser

struct CopyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "copy", abstract: "Duplicate an existing service.")

    @Argument(help: "Source service identifier.")
    var sourceIdentifier: String

    @Argument(help: "New service identifier.")
    var destinationIdentifier: String

    @Flag(help: "Enable the service after saving it.")
    var enable = false

    mutating func run() async throws {
        let source = try CLIParsing.identifier(sourceIdentifier)
        let destination = try CLIParsing.identifier(destinationIdentifier)
        let created = try await CLIContext.transfer.copyService(from: source, to: destination, enable: enable)
        print("Copied \(source.rawValue) to \(created.identifier.rawValue)\(enable ? " and enabled it" : "")")
    }
}
