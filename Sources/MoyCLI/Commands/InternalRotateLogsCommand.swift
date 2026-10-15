import ArgumentParser
import Foundation
import MoyKit

struct InternalRotateLogsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "internal-rotate-logs", shouldDisplay: false)

    mutating func run() async throws {
        do {
            try LocalLogRotationRepository().rotate()
        } catch let LogRotationError.files(failures) {
            throw ValidationError(failures.joined(separator: "\n"))
        } catch {
            throw ValidationError(error.localizedDescription)
        }
    }
}
