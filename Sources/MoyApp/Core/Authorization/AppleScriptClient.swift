import AppKit
import Carbon
import Foundation

struct AppleScriptClient: Sendable {
    var execute: @Sendable (_ source: String, _ handler: String, _ arguments: [String]) async throws -> String

    static let live = Self { source, handler, arguments in
        try await MainActor.run {
            let keyWindow = NSApp.keyWindow
            let window = keyWindow?.sheetParent ?? keyWindow ?? NSApp.mainWindow
            // Administrator authentication can leave this menu bar app behind other apps.
            // Restore the original window for success, cancellation and script errors alike.
            defer {
                if let window, !window.isMiniaturized {
                    NSApp.activate()
                    window.makeKeyAndOrderFront(nil)
                }
            }
            return try AppleScriptExecutor.execute(source: source, handler: handler, arguments: arguments)
        }
    }
}

@MainActor
private enum AppleScriptExecutor {
    static func execute(source: String, handler: String, arguments: [String]) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw AdministratorAuthorizationError.failed("Could not execute the authorization script.")
        }

        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent),
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID),
        )
        event.setParam(NSAppleEventDescriptor(string: handler.lowercased()), forKeyword: AEKeyword(keyASSubroutineName))
        // Argument descriptors preserve quotes, newlines and shell syntax as data.
        let parameters = NSAppleEventDescriptor.list()
        for (index, argument) in arguments.enumerated() {
            parameters.insert(NSAppleEventDescriptor(string: argument), at: index + 1)
        }
        event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))

        var errorInfo: NSDictionary?
        let result = script.executeAppleEvent(event, error: &errorInfo)
        if let errorInfo {
            if (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -128 {
                throw CancellationError()
            }
            throw AdministratorAuthorizationError.failed(
                errorInfo[NSAppleScript.errorMessage] as? String ?? "Could not execute the authorization script.",
            )
        }
        guard let output = result.stringValue else {
            throw AdministratorAuthorizationError.failed("Could not execute the authorization script.")
        }
        return output
    }
}
