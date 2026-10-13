import ArgumentParser
import Foundation

struct ImportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import", abstract: "Import a service from a JSON file.",
    )

    @Argument(help: "Service JSON file path.")
    var file: String

    @Flag(help: "Enable the service after saving it.")
    var enable = false

    mutating func run() async throws {
        let created = try await CLIContext.transfer.importService(from: URL(filePath: file), enable: enable)
        print("Imported \(created.identifier.rawValue)\(enable ? " and enabled it" : "")")
    }
}
