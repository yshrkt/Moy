import Foundation

/// Root operations access user files through an unprivileged subprocess, never by changing
/// process-wide credentials or writing root-owned files into the user's settings directory.
public struct UserServiceRepository: ServiceRepository, ServiceDocumentRepository, LaunchdRepository {
    public let userID: UInt32
    public let executable: String
    private let runner: any ProcessRunning

    public init(userID: UInt32, executable: String, runner: any ProcessRunning = DefaultProcessRunner()) {
        self.userID = userID
        self.executable = executable
        self.runner = runner
    }

    public func list() async throws -> [ServiceDefinition] {
        guard let services = try await request(.list).services else {
            throw MoyError.operationFailed("Missing services in repository response")
        }
        return services
    }

    public func find(identifier: ServiceIdentifier) async throws -> ServiceDefinition {
        guard let service = try await request(.find(identifier)).service else {
            throw MoyError.serviceNotFound(identifier.rawValue)
        }
        return service
    }

    public func create(_ service: ServiceDraft) async throws -> ServiceDefinition {
        guard let created = try await request(.create(service)).service else {
            throw MoyError.operationFailed("Missing service in repository response")
        }
        return created
    }

    public func update(_ service: ServiceDefinition) async throws {
        _ = try await request(.update(service, nil))
    }

    public func update(_ service: ServiceDefinition, expected: ServiceDefinition) async throws {
        _ = try await request(.update(service, expected))
    }

    public func remove(identifier: ServiceIdentifier) async throws {
        _ = try await request(.remove(identifier))
    }

    public func read(from url: URL) async throws -> ServiceJSONDocument {
        guard let document = try await request(.readDocument(url)).document else {
            throw MoyError.operationFailed("Missing document in repository response")
        }
        return document
    }

    public func write(_ document: ServiceJSONDocument, to url: URL) async throws {
        _ = try await request(.writeDocument(document, url))
    }

    public func status(identifier: ServiceIdentifier) async throws -> ServiceStatus {
        guard let status = try await request(.status(identifier)).status else {
            throw MoyError.operationFailed("Missing status in repository response")
        }
        return status
    }

    public func enable(_ service: ServiceDefinition) async throws {
        _ = try await request(.enable(service))
    }

    public func disable(identifier: ServiceIdentifier) async throws {
        _ = try await request(.disable(identifier))
    }

    public func restart(identifier: ServiceIdentifier) async throws {
        _ = try await request(.restart(identifier))
    }

    private func request(_ request: UserRepositoryRequest) async throws -> UserRepositoryResponse {
        let payload = try JSONEncoder().encode(request).base64EncodedString()
        let result = try await runner.run(executable: "/usr/bin/sudo", arguments: [
            "-H", "-u", "#\(userID)", "--", "/usr/bin/env", "-i",
            "PATH=/usr/bin:/bin:/usr/sbin:/sbin", executable, "internal-repository", payload,
        ])
        guard result.status == 0, let data = result.output.data(using: .utf8) else {
            throw MoyError.operationFailed(result.output)
        }
        let response = try JSONDecoder().decode(UserRepositoryResponse.self, from: data)
        if let error = response.error {
            throw error
        }
        return response
    }
}

extension UserServiceRepository: ServiceLogRepository {
    public func prepare(for service: ServiceDefinition) async throws {
        _ = try await request(.prepareLogs(service))
    }
}

public enum UserRepositoryRequest: Codable, Sendable {
    case prepareLogs(ServiceDefinition)
    case status(ServiceIdentifier)
    case enable(ServiceDefinition)
    case disable(ServiceIdentifier)
    case restart(ServiceIdentifier)
    case list
    case find(ServiceIdentifier)
    case create(ServiceDraft)
    case update(ServiceDefinition, ServiceDefinition?)
    case remove(ServiceIdentifier)
    case readDocument(URL)
    case writeDocument(ServiceJSONDocument, URL)
}

public struct UserRepositoryResponse: Codable, Sendable {
    public var status: ServiceStatus?
    public var services: [ServiceDefinition]?
    public var service: ServiceDefinition?
    public var document: ServiceJSONDocument?
    public var error: MoyError?

    public init() {}
}
