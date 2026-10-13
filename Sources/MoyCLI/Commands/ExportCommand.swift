import ArgumentParser
import Foundation

struct ExportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "export", abstract: "Export a service to a JSON file.")

    @Argument(help: "Service identifier.")
    var identifier: String

    @Option(help: "Output JSON file path. Existing files are overwritten.")
    var output: String

    mutating func run() async throws {
        let parsedIdentifier = try CLIParsing.identifier(identifier)
        try await CLIContext.transfer.exportService(identifier: parsedIdentifier, to: URL(filePath: output))
        print("Exported \(parsedIdentifier.rawValue) to \(output)")
    }
}
