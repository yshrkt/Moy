import ArgumentParser

struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show a service definition.")

    @Argument(help: "Service identifier.")
    var identifier: String

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    mutating func run() async throws {
        let service = try await CLIContext.services.find(identifier: CLIParsing.identifier(identifier))
        if json {
            try CLIOutput.json(service)
        } else {
            CLIOutput.service(service)
        }
    }
}
