import AppKit
import Foundation
import MoyKit

struct ServicesDependencies: Sendable {
    let serviceManagementUseCase: any ServiceManagementUseCase
    let serviceTransferUseCase: any ServiceTransferUseCase
    let transferFilePanelClient: ServiceTransferFilePanelClient
    let editor: ServiceEditorDependencies
    let workspaceClient: WorkspaceClient
    let clipboardClient: ClipboardClient
    let sleepForCopyToast: @Sendable (Duration) async throws -> Void

    init(
        serviceManagementUseCase: any ServiceManagementUseCase,
        serviceTransferUseCase: (any ServiceTransferUseCase)? = nil,
        transferFilePanelClient: ServiceTransferFilePanelClient = .live,
        editor: ServiceEditorDependencies = .init(),
        workspaceClient: WorkspaceClient = .live,
        clipboardClient: ClipboardClient = .live,
        sleepForCopyToast: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    ) {
        self.serviceManagementUseCase = serviceManagementUseCase
        self.serviceTransferUseCase = serviceTransferUseCase
            ?? DefaultServiceTransferUseCase(serviceManagementUseCase: serviceManagementUseCase)
        self.transferFilePanelClient = transferFilePanelClient
        self.editor = editor
        self.workspaceClient = workspaceClient
        self.clipboardClient = clipboardClient
        self.sleepForCopyToast = sleepForCopyToast
    }
}

struct ClipboardClient: Sendable {
    var copy: @Sendable (String) async -> Bool

    static let live = Self { value in
        await MainActor.run { CommandClipboard.copy(value) }
    }
}

struct WorkspaceClient: Sendable {
    var open: @Sendable (String) async throws -> Void
    var reveal: @Sendable (String) async throws -> Void

    static let live = Self(
        open: { path in
            guard FileManager.default.fileExists(atPath: path) else {
                throw AppOperationError.fileNotFound(path)
            }
            let didOpen = await MainActor.run {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
            guard didOpen else {
                throw AppOperationError.fileOperation(path)
            }
        },
        reveal: { path in
            let fileManager = FileManager.default
            let url = URL(fileURLWithPath: path)
            let exists = (try? fileManager.attributesOfItem(atPath: path)) != nil
            let target = exists ? url : url.deletingLastPathComponent()
            guard exists || fileManager.fileExists(atPath: target.path) else {
                throw AppOperationError.fileNotFound(path)
            }
            await MainActor.run {
                if target == url {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else {
                    NSWorkspace.shared.open(target)
                }
            }
        },
    )
}

enum AppOperationError: Error, Sendable {
    case fileNotFound(String)
    case fileOperation(String)
}
