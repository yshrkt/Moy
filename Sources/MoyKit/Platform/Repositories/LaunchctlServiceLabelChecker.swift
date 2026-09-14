import Darwin

public protocol ServiceLabelChecking: Sendable {
    func isLoaded(label: String) async throws -> Bool
}

public struct LaunchctlServiceLabelChecker: ServiceLabelChecking {
    private let processRunner: any ProcessRunning
    private let userID: uid_t

    public init(
        processRunner: any ProcessRunning = DefaultProcessRunner(),
        userID: uid_t = getuid(),
    ) {
        self.processRunner = processRunner
        self.userID = userID
    }

    public func isLoaded(label: String) async throws -> Bool {
        let arguments = ["print", "gui/\(userID)/\(label)"]
        let result = try await processRunner.run(executable: "/bin/launchctl", arguments: arguments)
        if result.status == 0 {
            return true
        }
        if LaunchctlOutputParser.isMissingService(result.output) {
            return false
        }
        throw MoyError.launchctlFailed(
            arguments: arguments,
            status: result.status,
            message: result.output.isEmpty ? "No error message" : result.output,
        )
    }
}
