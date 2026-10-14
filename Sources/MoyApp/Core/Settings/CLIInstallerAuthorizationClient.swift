import Foundation

struct CLIInstallerAuthorizationClient: Sendable {
    var install: @Sendable (URL, URL) async throws -> Void

    var uninstall: @Sendable (URL, URL, String) async throws -> Void = { source, destination, target in
        try await AuthorizedCLIInstaller(scriptClient: .live)
            .uninstall(source: source, destination: destination, expectedTarget: target)
    }

    static let live = Self(install: { source, destination in
        try await AuthorizedCLIInstaller(scriptClient: .live)
            .install(source: source, destination: destination)
    })
}

struct AuthorizedCLIInstaller: Sendable {
    let scriptClient: AppleScriptClient

    func install(source: URL, destination: URL) async throws {
        let output = try await execute(
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

    func uninstall(source: URL, destination: URL, expectedTarget: String) async throws {
        let output = try await execute(
            Self.authorizationScript,
            "uninstallcli",
            [Self.unlinkCommand(source: source, destination: destination, expectedTarget: expectedTarget)],
        )
        switch output {
        case "uninstalled": return
        case "cancelled": throw CancellationError()
        case "changed": throw SettingsFailure.cliLinkChanged
        default: throw SettingsFailure.cliAuthorizationFailed(output)
        }
    }

    private func execute(_ source: String, _ handler: String, _ arguments: [String]) async throws -> String {
        do {
            return try await scriptClient.execute(source, handler, arguments)
        } catch let AdministratorAuthorizationError.failed(reason) {
            throw SettingsFailure.cliAuthorizationFailed(reason)
        }
    }

    static func unlinkCommand(source: URL, destination: URL, expectedTarget: String) -> String {
        """
        set -eu
        source=\(shellQuote(source.path))
        destination=\(shellQuote(destination.path))
        expected=\(shellQuote(expectedTarget))
        if [ ! -L "$destination" ] || [ ! -x "$source" ]; then exit 19; fi
        actual=$(/usr/bin/readlink -n "$destination" && /usr/bin/printf x) || exit 19
        expected="${expected}x"
        if [ "$actual" != "$expected" ]; then exit 19; fi
        /bin/rm "$destination"
        """
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
        AdministratorAuthorizationClient.shellQuote(value)
    }

    static let authorizationScript = AdministratorAuthorizationClient.script + "\n" + """
    on installCLI(command)
        try
            executeCommand(command)
            return "installed"
        on error errorMessage number errorNumber
            if errorNumber is -128 then return "cancelled"
            if errorNumber is 17 then return "conflict"
            if errorNumber is 18 then return "missing"
            error errorMessage number errorNumber
        end try
    end installCLI

    on uninstallCLI(command)
        try
            executeCommand(command)
            return "uninstalled"
        on error errorMessage number errorNumber
            if errorNumber is -128 then return "cancelled"
            if errorNumber is 19 then return "changed"
            error errorMessage number errorNumber
        end try
    end uninstallCLI
    """
}
