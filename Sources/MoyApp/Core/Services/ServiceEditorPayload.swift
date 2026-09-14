import Foundation
import MoyKit

enum ServiceEditorPayload: Sendable {
    case create(ServiceIdentifier, ServiceDraft)
    case update(ServiceDefinition)

    var identifier: ServiceIdentifier {
        switch self {
        case let .create(identifier, _): identifier
        case let .update(definition): definition.identifier
        }
    }

    init(editor: ServiceEditorState) throws {
        let identifier = try ServiceIdentifier(editor.identifier)
        let throttleInterval = try Self.parseThrottleInterval(editor.throttleInterval)
        let environmentVariables = try Self.parseEnvironmentVariables(editor.environmentVariables)
        let standardOutPath = editor.standardOutPath.nilIfEmpty
        let standardErrorPath = editor.standardErrorPath.nilIfEmpty

        let values = Values(
            identifier: identifier,
            editor: editor,
            environmentVariables: environmentVariables,
            throttleInterval: throttleInterval,
        )
        switch editor.mode {
        case .create:
            self = .create(identifier, values.draft(
                standardOutPath: standardOutPath,
                standardErrorPath: standardErrorPath,
            ))
        case .edit:
            guard let standardOutPath, let standardErrorPath else {
                throw MoyError.invalidService(["StandardOutPath and StandardErrorPath are required."])
            }
            self = .update(values.definition(
                standardOutPath: standardOutPath,
                standardErrorPath: standardErrorPath,
            ))
        }
    }

    private static func parseThrottleInterval(_ rawValue: String) throws -> Int? {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return nil }
        guard let value = Int(rawValue), value > 0 else {
            throw ServicesFailure.invalidThrottleInterval
        }
        return value
    }

    private static func parseEnvironmentVariables(
        _ variables: [ServiceEditorState.EnvironmentVariable],
    ) throws -> [String: String] {
        var result: [String: String] = [:]
        for variable in variables {
            let key = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw ServicesFailure.emptyEnvironmentKey }
            guard result[key] == nil else { throw ServicesFailure.duplicateEnvironmentKey(key) }
            result[key] = variable.value
        }
        return result
    }
}

private struct Values {
    let identifier: ServiceIdentifier
    let displayName: String?
    let description: String?
    let programArguments: [String]
    let workingDirectory: String?
    let environmentVariables: [String: String]
    let runAtLoad: Bool
    let keepAlive: Bool
    let throttleInterval: Int?

    init(
        identifier: ServiceIdentifier,
        editor: ServiceEditorState,
        environmentVariables: [String: String],
        throttleInterval: Int?,
    ) {
        self.identifier = identifier
        displayName = editor.displayName.nilIfEmpty
        description = editor.serviceDescription.nilIfEmpty
        programArguments = [editor.executable.trimmingCharacters(in: .whitespacesAndNewlines)]
            + editor.arguments.map(\.value)
        workingDirectory = editor.workingDirectory.nilIfEmpty
        self.environmentVariables = environmentVariables
        runAtLoad = editor.runAtLoad
        keepAlive = editor.keepAlive
        self.throttleInterval = throttleInterval
    }

    func draft(
        standardOutPath: String?,
        standardErrorPath: String?,
    ) -> ServiceDraft {
        ServiceDraft(
            identifier: identifier,
            displayName: displayName,
            description: description,
            programArguments: programArguments,
            workingDirectory: workingDirectory,
            environmentVariables: environmentVariables,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            throttleInterval: throttleInterval,
            standardOutPath: standardOutPath,
            standardErrorPath: standardErrorPath,
        )
    }

    func definition(
        standardOutPath: String,
        standardErrorPath: String,
    ) -> ServiceDefinition {
        ServiceDefinition(
            identifier: identifier,
            displayName: displayName,
            description: description,
            programArguments: programArguments,
            workingDirectory: workingDirectory,
            environmentVariables: environmentVariables,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            throttleInterval: throttleInterval,
            standardOutPath: standardOutPath,
            standardErrorPath: standardErrorPath,
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
