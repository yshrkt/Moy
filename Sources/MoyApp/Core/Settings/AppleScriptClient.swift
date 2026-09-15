import Carbon
import Foundation

struct AppleScriptClient: Sendable {
    var execute: @Sendable (_ source: String, _ handler: String, _ arguments: [String]) async throws -> String

    static let live = Self { source, handler, arguments in
        try await MainActor.run {
            try AppleScriptExecutor.execute(source: source, handler: handler, arguments: arguments)
        }
    }
}

@MainActor
private enum AppleScriptExecutor {
    static func execute(source: String, handler: String, arguments: [String]) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw SettingsFailure.cliAuthorizationFailed(L10n.Error.cliInstallationFailed)
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
            throw SettingsFailure.cliAuthorizationFailed(
                errorInfo[NSAppleScript.errorMessage] as? String ?? L10n.Error.cliInstallationFailed,
            )
        }
        guard let output = result.stringValue else {
            throw SettingsFailure.cliAuthorizationFailed(L10n.Error.cliInstallationFailed)
        }
        return output
    }
}
