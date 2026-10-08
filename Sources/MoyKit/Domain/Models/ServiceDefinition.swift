import Foundation

public struct ServiceDefinition: Codable, Equatable, Identifiable, Sendable {
    public let identifier: ServiceIdentifier
    public let kind: ServiceKind
    public var displayName: String?
    public var description: String?
    public var programArguments: [String]
    public var workingDirectory: String?
    public var environmentVariables: [String: String]
    public var runAtLoad: Bool
    public var keepAlive: Bool
    public var throttleInterval: Int?
    public var standardOutPath: String
    public var standardErrorPath: String

    public var id: ServiceIdentifier {
        identifier
    }

    public init(
        identifier: ServiceIdentifier,
        kind: ServiceKind = .launchAgent,
        displayName: String? = nil,
        description: String? = nil,
        programArguments: [String],
        workingDirectory: String? = nil,
        environmentVariables: [String: String] = [:],
        runAtLoad: Bool = false,
        keepAlive: Bool = false,
        throttleInterval: Int? = nil,
        standardOutPath: String,
        standardErrorPath: String,
    ) {
        self.identifier = identifier
        self.kind = kind
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

    public var name: String {
        guard let displayName, !displayName.isEmpty else { return identifier.rawValue }
        return displayName
    }

    public func hasSameLaunchConfiguration(as other: Self) -> Bool {
        kind == other.kind
            && programArguments == other.programArguments
            && workingDirectory == other.workingDirectory
            && environmentVariables == other.environmentVariables
            && runAtLoad == other.runAtLoad
            && keepAlive == other.keepAlive
            && throttleInterval == other.throttleInterval
            && standardOutPath == other.standardOutPath
            && standardErrorPath == other.standardErrorPath
    }
}
