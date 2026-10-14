import ArgumentParser
import Darwin
import Foundation
import MoyKit

struct InternalDaemonCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "internal-daemon", shouldDisplay: false)

    @Argument var userID: UInt32
    @Argument var payload: String

    mutating func run() async throws {
        guard geteuid() == 0 else { throw MoyError.administratorRequired }
        let user = try MoyUserContext.resolve(requestedUserID: userID)
        guard let data = Data(base64Encoded: payload) else { throw ValidationError("Invalid daemon request") }
        let request = try JSONDecoder().decode(DaemonOperation.self, from: data)
        var response = DaemonOperationResult()
        do {
            let expected = request.expected
            let repository = try UserServiceRepository(userID: user.userID, executable: CLIContext.executablePath())
            let services = MoyRuntime.makeServiceManagementUseCase(
                paths: user.paths, userID: user.userID,
                repository: ReviewedServiceRepository(base: repository, expected: expected),
            )
            guard expected.kind == .launchDaemon,
                  try await services.find(identifier: expected.identifier) == expected
            else {
                throw MoyError.serviceChanged
            }
            switch request.action {
            case .enable: try await services.enable(identifier: expected.identifier)
            case .disable: try await services.disable(identifier: expected.identifier)
            case .restart: try await services.restart(identifier: expected.identifier)
            case .remove: try await services.remove(identifier: expected.identifier)
            case .update:
                guard let updated = request.updated, updated.identifier == expected.identifier,
                      updated.kind == expected.kind else { throw MoyError.kindCannotChange }
                try await services.update(updated)
            }
        } catch {
            response.error = (error as? MoyError) ?? .operationFailed(error.localizedDescription)
        }
        try CLIOutput.json(response)
    }
}
