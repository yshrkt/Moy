import Foundation
import NanoRedux

struct ServiceEditorReducer: InjectableReducer {
    let dependencies: ServiceEditorDependencies

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func reduce(into state: inout ServiceEditorState, action: ServiceEditorAction) -> Effect<ServiceEditorAction> {
        switch action {
        case .cancel:
            guard !state.isSaving else { return .none }
            state.validatingIdentifier = nil
            let id = state.id
            return .run { .delegate(.cancel(id)) }

        case .dismissFailure:
            state.failure = nil
            return .none

        case .save:
            guard !state.isSaving, state.validatingIdentifier == nil else { return .none }
            state.failure = nil
            if case .create = state.mode {
                state.identifierIssue = ServiceEditorIdentifierValidator.validate(
                    state.identifier, existingIdentifiers: state.existingIdentifiers,
                )
            }
            guard state.identifierIssue == nil else { return .none }
            do {
                let payload = try ServiceEditorPayload(editor: state)
                state.isSaving = true
                let id = state.id
                return .run { .delegate(.save(id, payload)) }
            } catch {
                state.failure = .from(error)
                return .none
            }

        case let .receiveSave(result):
            state.isSaving = false
            if case let .failure(failure) = result {
                state.failure = failure == .cancelled ? nil : failure
            }
            return .none

        case .delegate:
            return .none

        case let .updateExistingIdentifiers(identifiers):
            guard state.existingIdentifiers != identifiers else { return .none }
            state.existingIdentifiers = identifiers
            return validateIdentifier(into: &state)

        case let .receiveIdentifierValidation(sessionID, identifier, issue):
            guard state.id == sessionID, state.identifier == identifier else { return .none }
            state.validatingIdentifier = nil
            state.identifierIssue = issue
            return .none

        case let .updateField(field):
            guard !state.isSaving else { return .none }
            let editor = state
            switch field {
            case let .kind(value):
                guard editor.canChangeKind else { return .none }
                editor.kind = value
            case let .identifier(value):
                guard case .create = editor.mode else { return .none }
                editor.identifier = value
                return validateIdentifier(into: &state)
            case let .displayName(value):
                editor.displayName = value
            case let .description(value):
                editor.serviceDescription = value
            case let .executable(value):
                editor.executable = value
            case let .workingDirectory(value):
                editor.workingDirectory = value
            case let .runAtLoad(value):
                editor.runAtLoad = value
            case let .keepAlive(value):
                editor.keepAlive = value
            case let .throttleInterval(value):
                editor.throttleInterval = value
            case let .standardOutPath(value):
                editor.standardOutPath = value
            case let .standardErrorPath(value):
                editor.standardErrorPath = value
            }
            return .none

        case let .arguments(action):
            reduceArguments(into: &state, action: action)
            return .none

        case let .environment(action):
            reduceEnvironment(into: &state, action: action)
            return .none

        case let .choosePath(path):
            guard !state.isSaving else { return .none }
            let sessionID = state.id
            let filePanelClient = dependencies.filePanelClient
            return .run(lifetime: .replaceable("serviceEditor.choosePath")) {
                let selectedPath = await filePanelClient.choosePath(path)
                return .receivePath(sessionID, path, selectedPath)
            }

        case let .receivePath(sessionID, path, selectedPath):
            guard state.id == sessionID else { return .none }
            guard let selectedPath else { return .none }
            let field: ServiceEditorField = switch path {
            case .executable: .executable(selectedPath)
            case .workingDirectory: .workingDirectory(selectedPath)
            case .standardOut: .standardOutPath(selectedPath)
            case .standardError: .standardErrorPath(selectedPath)
            }
            return reduce(into: &state, action: .updateField(field))
        }
    }

    private func validateIdentifier(into state: inout ServiceEditorState) -> Effect<ServiceEditorAction> {
        guard case .create = state.mode else { return .none }
        let sessionID = state.id
        let identifier = state.identifier
        let existingIdentifiers = state.existingIdentifiers
        state.validatingIdentifier = identifier
        return .debounce(for: .milliseconds(300), key: "serviceEditor.identifierValidation") {
            Effect.run {
                let issue = ServiceEditorIdentifierValidator.validate(
                    identifier, existingIdentifiers: existingIdentifiers,
                )
                return .receiveIdentifierValidation(sessionID, identifier, issue)
            }
        }
    }
}
