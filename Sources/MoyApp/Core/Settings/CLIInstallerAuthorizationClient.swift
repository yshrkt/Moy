import Foundation

struct CLIInstallerAuthorizationClient: Sendable {
    var install: @Sendable (URL, URL) async throws -> Void

    static let live = Self { source, destination in
        try await AuthorizedCLIInstaller(scriptClient: .live)
            .install(source: source, destination: destination)
    }
}

struct AuthorizedCLIInstaller: Sendable {
    let scriptClient: AppleScriptClient

    func install(source: URL, destination: URL) async throws {
        let output = try await scriptClient.execute(
            Self.authorizationScript,
            "installcli",
            [Self.linkCommand(source: source, destination: destination)],
        )
        switch output {
        case "installed":
            return
        case "cancelled":
            throw CancellationError()
        case "conflict":
            throw SettingsFailure.cliDestinationExists
        case "missing":
            throw SettingsFailure.cliNotBundled
        default:
            throw SettingsFailure.cliAuthorizationFailed(output)
        }
    }

    static func linkCommand(source: URL, destination: URL) -> String {
        """
        set -eu
        source=\(shellQuote(source.path))
        destination=\(shellQuote(destination.path))
        if [ -e "$destination" ] || [ -L "$destination" ]; then exit 17; fi
        if [ ! -x "$source" ]; then exit 18; fi
        /bin/mkdir -p \(shellQuote(destination.deletingLastPathComponent().path))
        /bin/ln -s -h "$source" "$destination"
        """
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    static let authorizationScript = """
    on installCLI(command)
        try
            do shell script command with administrator privileges
            return "installed"
        on error errorMessage number errorNumber
            if errorNumber is -128 then return "cancelled"
            if errorNumber is 17 then return "conflict"
            if errorNumber is 18 then return "missing"
            error errorMessage number errorNumber
        end try
    end installCLI
    """
}
