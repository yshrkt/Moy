import AppKit
import Foundation
import MoyKit

struct ServicesDependencies: Sendable {
    let serviceManagementUseCase: any ServiceManagementUseCase
    let filePanelClient: FilePanelClient
    let workspaceClient: WorkspaceClient
    let cliInstallerClient: CLIInstallerClient

    init(
        serviceManagementUseCase: any ServiceManagementUseCase,
        filePanelClient: FilePanelClient = .live,
        workspaceClient: WorkspaceClient = .live,
        cliInstallerClient: CLIInstallerClient = .live,
    ) {
        self.serviceManagementUseCase = serviceManagementUseCase
        self.filePanelClient = filePanelClient
        self.workspaceClient = workspaceClient
        self.cliInstallerClient = cliInstallerClient
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

struct CLIInstallerClient: Sendable {
    var install: @Sendable () async throws -> String

    static let live: Self = {
        let installer = CLIInstaller()
        return Self {
            try await installer.install()
        }
    }()
}

enum AppOperationError: Error, Sendable {
    case fileNotFound(String)
    case fileOperation(String)
    case cliNotBundled
    case cliDestinationExists(String)
}

private actor CLIInstaller {
    func install() throws -> String {
        let sourceURL = Bundle.main.bundleURL
            .appending(path: "Contents/Helpers/moy", directoryHint: .notDirectory)
        guard FileManager.default.isExecutableFile(atPath: sourceURL.path) else {
            throw AppOperationError.cliNotBundled
        }

        let fileManager = FileManager.default
        let binURL = fileManager.homeDirectoryForCurrentUser
            .appending(path: ".local/bin", directoryHint: .isDirectory)
        let destinationURL = binURL.appending(path: "moy", directoryHint: .notDirectory)

        if fileManager.fileExists(atPath: destinationURL.path) {
            if let target = try? fileManager.destinationOfSymbolicLink(atPath: destinationURL.path),
               URL(fileURLWithPath: target).standardizedFileURL == sourceURL.standardizedFileURL
            {
                return destinationURL.path
            }
            throw AppOperationError.cliDestinationExists(destinationURL.path)
        }

        do {
            try fileManager.createDirectory(at: binURL, withIntermediateDirectories: true)
            try fileManager.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: binURL.path,
            )
            try fileManager.createSymbolicLink(
                at: destinationURL,
                withDestinationURL: sourceURL,
            )
            return destinationURL.path
        } catch let error as AppOperationError {
            throw error
        } catch {
            throw AppOperationError.fileOperation(error.localizedDescription)
        }
    }
}
