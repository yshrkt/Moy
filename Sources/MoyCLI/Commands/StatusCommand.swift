import ArgumentParser

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Show launchd service status.")

    @Argument(help: "Optional service identifier. Omit it to show every service.")
    var identifier: String?

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    mutating func run() async throws {
        if let identifier {
            let status = try await CLIContext.services.status(identifier: CLIParsing.identifier(identifier))
            if json {
                try CLIOutput.json(status)
            } else {
                print("IDENTIFIER\tREGISTRATION\tRUNTIME\tLAST EXIT")
                CLIOutput.status(status)
            }
            return
        }

        let statuses = try await CLIContext.services.statuses()
        if json {
            try CLIOutput.json(statuses)
        } else if statuses.isEmpty {
            print("No services registered.")
        } else {
            print("IDENTIFIER\tREGISTRATION\tRUNTIME\tLAST EXIT")
            statuses.forEach(CLIOutput.status)
        }
    }
}
