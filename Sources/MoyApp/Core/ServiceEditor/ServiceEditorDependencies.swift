import AppKit
import Foundation

struct ServiceEditorDependencies: Sendable {
    var filePanelClient: FilePanelClient = .live
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
