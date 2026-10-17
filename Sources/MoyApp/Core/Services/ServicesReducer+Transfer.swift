import MoyKit
import NanoRedux

extension ServicesReducer {
    func reduceTransfer(
        into state: inout ServicesState, action: ServicesTransferAction,
    ) -> Effect<ServicesTransferAction> {
        switch action {
        case .importService:
            return startImport(into: &state)

        case let .receiveImport(result):
            return finishImport(result, into: &state)

        case let .exportService(identifier):
            return startExport(identifier, into: &state)

        case let .receiveExport(identifier, result):
            guard state.transferOperation == .exportService(identifier) else { return .none }
            state.transferOperation = nil
            if case let .failure(failure) = result {
                state.failure = failure
            }
            return .none
        }
    }

    private func startImport(into state: inout ServicesState) -> Effect<ServicesTransferAction> {
        guard state.canOpenEditor else { return .none }
        state.failure = nil
        state.transferOperation = .importService
        let panels = dependencies.transferFilePanelClient
        let transfer = dependencies.serviceTransferUseCase
        return .run {
            guard let url = await panels.chooseImportFile() else { return .receiveImport(.success(nil)) }
            do {
                let draft = try await transfer.readService(from: url)
                return .receiveImport(.success(draft))
            } catch {
                return .receiveImport(.failure(.from(error)))
            }
        }
    }

    private func startExport(
        _ identifier: ServiceIdentifier, into state: inout ServicesState,
    ) -> Effect<ServicesTransferAction> {
        guard state.canOpenEditor, !state.isOperating(identifier),
              state.services.contains(where: { $0.identifier == identifier }) else { return .none }
        state.failure = nil
        state.transferOperation = .exportService(identifier)
        let panels = dependencies.transferFilePanelClient
        let transfer = dependencies.serviceTransferUseCase
        return .run {
            guard let url = await panels.chooseExportFile(identifier) else {
                return .receiveExport(identifier, .success(()))
            }
            do {
                try await transfer.exportService(identifier: identifier, to: url)
                return .receiveExport(identifier, .success(()))
            } catch {
                return .receiveExport(identifier, .failure(.from(error)))
            }
        }
    }

    private func finishImport(
        _ result: Result<ServiceDraft?, ServicesFailure>, into state: inout ServicesState,
    ) -> Effect<ServicesTransferAction> {
        guard state.transferOperation == .importService else { return .none }
        state.transferOperation = nil
        switch result {
        case let .success(draft?):
            let identifiers = Set(state.services.map(\.identifier.rawValue))
            let editor = ServiceEditorState.create(draft: draft, existingIdentifiers: identifiers)
            editor.identifierIssue = ServiceEditorIdentifierValidator.validate(
                editor.identifier, existingIdentifiers: identifiers,
            )
            state.editor = editor
        case .success(nil): break
        case let .failure(failure): state.failure = failure
        }
        return .none
    }
}
