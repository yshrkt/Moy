import AppKit
import Foundation
import MoyKit
import UniformTypeIdentifiers

struct ServiceTransferFilePanelClient: Sendable {
    var chooseImportFile: @Sendable () async -> URL?
    var chooseExportFile: @Sendable (ServiceIdentifier) async -> URL?

    static let live = Self(
        chooseImportFile: {
            await MainActor.run {
                let panel = NSOpenPanel()
                panel.title = L10n.Services.importTitle
                panel.allowedContentTypes = [.json]
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                return panel.runModal() == .OK ? panel.url : nil
            }
        },
        chooseExportFile: { identifier in
            await MainActor.run {
                let panel = NSSavePanel()
                panel.title = L10n.Services.exportTitle
                panel.allowedContentTypes = [.json]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = "\(identifier.rawValue).json"
                return panel.runModal() == .OK ? panel.url : nil
            }
        },
    )
}
