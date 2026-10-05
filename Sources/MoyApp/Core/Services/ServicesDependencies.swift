import AppKit
import Foundation
import MoyKit

struct ServicesDependencies: Sendable {
    let serviceManagementUseCase: any ServiceManagementUseCase
    let filePanelClient: FilePanelClient
    let workspaceClient: WorkspaceClient
    let clipboardClient: ClipboardClient
    let sleepForCopyToast: @Sendable (Duration) async throws -> Void

    init(
        serviceManagementUseCase: any ServiceManagementUseCase,
        filePanelClient: FilePanelClient = .live,
        workspaceClient: WorkspaceClient = .live,
        clipboardClient: ClipboardClient = .live,
        sleepForCopyToast: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    ) {
        self.serviceManagementUseCase = serviceManagementUseCase
        self.filePanelClient = filePanelClient
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

struct FilePanelClient: Sendable {
    var choosePath: @Sendable (ServiceEditorPath) async -> String?

    static let live = Self { path in
        await MainActor.run {
            switch path {
            case .executable:
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                return panel.runModal() == .OK ? panel.url?.path : nil
            case .workingDirectory:
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                return panel.runModal() == .OK ? panel.url?.path : nil
            case .standardOut, .standardError:
                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                return panel.runModal() == .OK ? panel.url?.path : nil
            }
        }
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
            let target = fileManager.fileExists(atPath: path) ? url : url.deletingLastPathComponent()
            guard fileManager.fileExists(atPath: target.path) else {
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
