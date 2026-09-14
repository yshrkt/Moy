public struct ServiceDraft: Equatable, Sendable {
    public var identifier: ServiceIdentifier
    public var displayName: String?
    public var description: String?
    public var programArguments: [String]
    public var workingDirectory: String?
    public var environmentVariables: [String: String]
    public var runAtLoad: Bool
    public var keepAlive: Bool
    public var throttleInterval: Int?
    public var standardOutPath: String?
    public var standardErrorPath: String?

    public init(
        identifier: ServiceIdentifier,
        displayName: String? = nil,
        description: String? = nil,
        programArguments: [String],
        workingDirectory: String? = nil,
        environmentVariables: [String: String] = [:],
        runAtLoad: Bool = false,
        keepAlive: Bool = false,
        throttleInterval: Int? = nil,
        standardOutPath: String? = nil,
        standardErrorPath: String? = nil,
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.description = description
        self.programArguments = programArguments
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.throttleInterval = throttleInterval
        self.standardOutPath = standardOutPath
        self.standardErrorPath = standardErrorPath
    }
}
