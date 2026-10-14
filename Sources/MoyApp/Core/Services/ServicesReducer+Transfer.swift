import MoyKit
import NanoRedux

extension ServicesReducer {
    func reduceTransfer(into state: inout ServicesState, action: ServicesAction) -> Effect<ServicesAction> {
        switch action {
        case .importService:
            return startImport(into: &state)

        case let .receiveImportService(result):
            return finishImport(result, into: &state)

        case let .exportService(identifier):
            return startExport(identifier, into: &state)

        case let .receiveExportService(identifier, result):
            guard state.transferOperation == .exportService(identifier) else { return .none }
            state.transferOperation = nil
            if case let .failure(failure) = result {
                state.failure = failure
            }
            return .none

        default: return .none
        }
    }

    private func startImport(into state: inout ServicesState) -> Effect<ServicesAction> {
        guard state.canOpenEditor else { return .none }
        state.failure = nil
        state.transferOperation = .importService
        let panels = dependencies.transferFilePanelClient
        let transfer = dependencies.serviceTransferUseCase
        return .run {
            guard let url = await panels.chooseImportFile() else { return .receiveImportService(.success(nil)) }
            do {
                let draft = try await transfer.readService(from: url)
                return .receiveImportService(.success(draft))
            } catch {
                return .receiveImportService(.failure(.from(error)))
            }
        }
    }

    private func startExport(
        _ identifier: ServiceIdentifier, into state: inout ServicesState,
    ) -> Effect<ServicesAction> {
        guard state.canOpenEditor, !state.isOperating(identifier),
              state.services.contains(where: { $0.identifier == identifier }) else { return .none }
        state.failure = nil
        state.transferOperation = .exportService(identifier)
        let panels = dependencies.transferFilePanelClient
        let transfer = dependencies.serviceTransferUseCase
        return .run {
            guard let url = await panels.chooseExportFile(identifier) else {
                return .receiveExportService(identifier, .success(()))
            }
            do {
                try await transfer.exportService(identifier: identifier, to: url)
                return .receiveExportService(identifier, .success(()))
            } catch {
                return .receiveExportService(identifier, .failure(.from(error)))
            }
        }
    }

    private func finishImport(
        _ result: Result<ServiceDraft?, ServicesFailure>, into state: inout ServicesState,
    ) -> Effect<ServicesAction> {
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
