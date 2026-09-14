import ArgumentParser

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List service definitions.")

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    mutating func run() async throws {
        let services = try await CLIContext.services.list()
        if json {
            try CLIOutput.json(services)
            return
        }
        guard !services.isEmpty else {
            print("No services registered.")
            return
        }
        print("IDENTIFIER\tNAME\tPROGRAM")
        for service in services {
            print("\(service.identifier.rawValue)\t\(service.name)\t\(service.programArguments[0])")
        }
    }
}
