import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

public protocol ProcessRunning: Sendable {
    func run(executable: String, arguments: [String]) async throws -> ProcessResult
}

public struct DefaultProcessRunner: ProcessRunning {
    public init() {}

    public func run(executable: String, arguments: [String]) async throws -> ProcessResult {
        try await Task.detached {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(filePath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return ProcessResult(
                    status: process.terminationStatus,
                    output: (String(data: data, encoding: .utf8) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                )
            } catch {
                throw MoyError.fileOperation(path: executable, reason: error.localizedDescription)
            }
        }.value
    }
}
