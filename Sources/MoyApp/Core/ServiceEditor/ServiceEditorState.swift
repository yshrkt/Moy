import Foundation
import MoyKit
import NanoRedux
import Observation

typealias ServiceEditorStore = Store<ServiceEditorState, ServiceEditorAction>

enum ServiceEditorMode: Equatable, Sendable {
    case create
    case edit(ServiceIdentifier)
}

@Observable
final class ServiceEditorState {
    let id = UUID()
    var isSaving = false
    var failure: ServicesFailure?
    var existingIdentifiers: Set<String> = []

    var identifierIssue: ServiceEditorIdentifierIssue? = .invalidFormat(.empty)
    var validatingIdentifier: String?

    var canSave: Bool {
        !isSaving && validatingIdentifier == nil && identifierIssue == nil
            && !executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
    var selectedArgumentID: UUID?
    var workingDirectory: String
    var environmentVariables: [EnvironmentVariable]
    var selectedEnvironmentVariableID: UUID?
    var runAtLoad: Bool
    var keepAlive: Bool
    var throttleInterval: String
    var standardOutPath: String
    var standardErrorPath: String

    static func create(existingIdentifiers: Set<String> = []) -> Self {
        let state = Self(
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
        state.existingIdentifiers = existingIdentifiers
        return state
    }

    init(service: ServiceDefinition) {
        identifierIssue = nil
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

    static func create(draft: ServiceDraft, existingIdentifiers: Set<String>) -> Self {
        let state = Self(
            mode: .create,
            identifier: draft.identifier.rawValue,
            displayName: draft.displayName ?? "",
            serviceDescription: draft.description ?? "",
            executable: draft.programArguments.first ?? "",
            arguments: draft.programArguments.dropFirst().map { Argument(value: $0) },
            workingDirectory: draft.workingDirectory ?? "",
            environmentVariables: draft.environmentVariables.sorted { $0.key < $1.key }
                .map { EnvironmentVariable(key: $0.key, value: $0.value) },
            runAtLoad: draft.runAtLoad,
            keepAlive: draft.keepAlive,
            throttleInterval: draft.throttleInterval.map(String.init) ?? "",
            standardOutPath: draft.standardOutPath ?? "",
            standardErrorPath: draft.standardErrorPath ?? "",
        )
        state.existingIdentifiers = existingIdentifiers
        return state
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
