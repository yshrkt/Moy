import ArgumentParser
import Darwin
import Foundation
import MoyKit

struct InternalRepositoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "internal-repository", shouldDisplay: false)

    @Argument var payload: String

    // swiftlint:disable:next cyclomatic_complexity
    mutating func run() async throws {
        guard geteuid() != 0 else { throw MoyError.invalidInvokingUser }
        guard let data = Data(base64Encoded: payload) else { throw ValidationError("Invalid repository request") }
        let request = try JSONDecoder().decode(UserRepositoryRequest.self, from: data)
        let repository = JSONServiceRepository()
        let launch = LaunchctlServiceRepository()
        let documents = JSONServiceDocumentRepository()
        var response = UserRepositoryResponse()
        do {
            switch request {
            case let .prepareLogs(service): try await LocalServiceLogRepository().prepare(for: service)
            case let .status(identifier): response.status = try await launch.status(identifier: identifier)
            case let .enable(service):
                guard service.kind == .launchAgent else { throw MoyError.administratorRequired }
                try await launch.enable(service)
            case let .disable(identifier): try await launch.disable(identifier: identifier)
            case let .restart(identifier): try await launch.restart(identifier: identifier)
            case .list: response.services = try await repository.list()
            case let .find(identifier): response.service = try await repository.find(identifier: identifier)
            case let .create(draft): response.service = try await repository.create(draft)
            case let .update(service, expected):
                if let expected {
                    try await repository.update(service, expected: expected)
                } else {
                    try await repository.update(service)
                }
            case let .remove(identifier): try await repository.remove(identifier: identifier)
            case let .readDocument(url): response.document = try await documents.read(from: url)
            case let .writeDocument(document, url): try await documents.write(document, to: url)
            }
        } catch {
            response.error = (error as? MoyError) ?? .operationFailed(error.localizedDescription)
        }
        try CLIOutput.json(response)
    }
}
