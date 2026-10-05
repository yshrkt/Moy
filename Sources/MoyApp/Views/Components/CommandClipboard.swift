import AppKit

@MainActor
enum CommandClipboard {
    @discardableResult
    static func copy(_ command: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(command, forType: .string)
    }
}
