import Foundation
import MoyKit
import Observation

@Observable
final class ServicesState {
    var services: [ServiceDefinition] = []
    var statuses: [ServiceIdentifier: ServiceStatus] = [:]
    var statusFailures: Set<ServiceIdentifier> = []
    var selectedIdentifier: ServiceIdentifier?
    var editor: ServiceEditorState?
    var pendingDeletion: ServiceIdentifier?
    var operatingIdentifiers: Set<ServiceIdentifier> = []
    var isLoading = false
    var isSaving = false
    var isInstallingCLI = false
    var cliInstallationPath: String?
    var failure: ServicesFailure?

    var selectedService: ServiceDefinition? {
        guard let selectedIdentifier else { return nil }
        return services.first { $0.identifier == selectedIdentifier }
    }

    func isOperating(_ identifier: ServiceIdentifier) -> Bool {
        operatingIdentifiers.contains(identifier)
    }
}

struct ServicesSnapshot: Equatable, Sendable {
    let services: [ServiceDefinition]
    let statuses: [ServiceIdentifier: ServiceStatus]
    let statusFailures: Set<ServiceIdentifier>
}

enum ServiceEditorMode: Equatable, Sendable {
    case create
    case edit(ServiceIdentifier)
}

struct ServiceEditorState: Equatable, Sendable {
    struct Argument: Equatable, Identifiable, Sendable {
        let id: UUID
        var value: String

        init(id: UUID = UUID(), value: String = "") {
            self.id = id
            self.value = value
        }
    }

    struct EnvironmentVariable: Equatable, Identifiable, Sendable {
        let id: UUID
        var key: String
        var value: String

        init(id: UUID = UUID(), key: String = "", value: String = "") {
            self.id = id
            self.key = key
            self.value = value
        }
    }

    let mode: ServiceEditorMode
    var identifier: String
    var displayName: String
    var serviceDescription: String
    var executable: String
    var arguments: [Argument]
    var workingDirectory: String
    var environmentVariables: [EnvironmentVariable]
    var runAtLoad: Bool
    var keepAlive: Bool
    var throttleInterval: String
    var standardOutPath: String
    var standardErrorPath: String

    static func create() -> Self {
        Self(
            mode: .create,
            identifier: "",
            displayName: "",
            serviceDescription: "",
            executable: "",
            arguments: [],
            workingDirectory: "",
            environmentVariables: [],
            runAtLoad: false,
            keepAlive: false,
            throttleInterval: "",
            standardOutPath: "",
            standardErrorPath: "",
        )
    }

    init(service: ServiceDefinition) {
        mode = .edit(service.identifier)
        identifier = service.identifier.rawValue
        displayName = service.displayName ?? ""
        serviceDescription = service.description ?? ""
        executable = service.programArguments.first ?? ""
        arguments = service.programArguments.dropFirst().map { Argument(value: $0) }
        workingDirectory = service.workingDirectory ?? ""
        environmentVariables = service.environmentVariables
            .sorted { $0.key < $1.key }
            .map { EnvironmentVariable(key: $0.key, value: $0.value) }
        runAtLoad = service.runAtLoad
        keepAlive = service.keepAlive
        throttleInterval = service.throttleInterval.map(String.init) ?? ""
        standardOutPath = service.standardOutPath
        standardErrorPath = service.standardErrorPath
    }

    private init(
        mode: ServiceEditorMode,
        identifier: String,
        displayName: String,
        serviceDescription: String,
        executable: String,
        arguments: [Argument],
        workingDirectory: String,
        environmentVariables: [EnvironmentVariable],
        runAtLoad: Bool,
        keepAlive: Bool,
        throttleInterval: String,
        standardOutPath: String,
        standardErrorPath: String,
    ) {
        self.mode = mode
        self.identifier = identifier
        self.displayName = displayName
        self.serviceDescription = serviceDescription
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.throttleInterval = throttleInterval
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
    }
}

enum ServiceEditorField: Equatable, Sendable {
    case identifier(String)
    case displayName(String)
    case description(String)
    case executable(String)
    case workingDirectory(String)
    case runAtLoad(Bool)
    case keepAlive(Bool)
    case throttleInterval(String)
    case standardOutPath(String)
    case standardErrorPath(String)
}

enum ServiceEditorPath: Equatable, Sendable {
    case executable
    case workingDirectory
    case standardOut
    case standardError
}

enum ServicesFailure: Error, Equatable, Sendable {
    case moy(MoyError)
    case invalidThrottleInterval
    case emptyEnvironmentKey
    case duplicateEnvironmentKey(String)
    case fileNotFound(String)
    case cliNotBundled
    case cliDestinationExists(String)
    case unexpected(String)

    static func from(_ error: any Error) -> Self {
        if let error = error as? MoyError {
            return .moy(error)
        }
        if let error = error as? AppOperationError {
            switch error {
            case .cliNotBundled:
                return .cliNotBundled
            case let .cliDestinationExists(path):
                return .cliDestinationExists(path)
            case let .fileNotFound(path):
                return .fileNotFound(path)
            case let .fileOperation(message):
                return .unexpected(message)
            }
        }
        return .unexpected(error.localizedDescription)
    }
}
