import Foundation

struct AdministratorAuthorizationClient: Sendable {
    var execute: @Sendable (String) async throws -> String

    static let live = Self { command in
        try await AppleScriptClient.live.execute(script, "executeCommand", [command])
    }

    static let script = """
    on executeCommand(command)
        do shell script command with administrator privileges
    end executeCommand
    """

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

enum AdministratorAuthorizationError: Error, Equatable, Sendable {
    case failed(String)
}
