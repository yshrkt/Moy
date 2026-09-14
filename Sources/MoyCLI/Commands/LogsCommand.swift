import ArgumentParser

struct LogsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "logs", abstract: "Show service log file paths.")

    @Argument(help: "Service identifier.")
    var identifier: String

    @Flag(help: "Print machine-readable JSON.")
    var json = false

    mutating func run() async throws {
        let service = try await CLIContext.services.find(identifier: CLIParsing.identifier(identifier))
        if json {
            try CLIOutput.json(LogPaths(stdout: service.standardOutPath, stderr: service.standardErrorPath))
        } else {
            print("stdout: \(service.standardOutPath)")
            print("stderr: \(service.standardErrorPath)")
        }
    }
}

private struct LogPaths: Encodable {
    let stdout: String
    let stderr: String
}
