import Foundation

/// A fixed operation and the definition reviewed before the administrator prompt.
public struct DaemonOperation: Codable, Sendable {
    public enum Action: String, Codable, Sendable {
        case enable
        case disable
        case restart
        case remove
        case update
    }

    public let action: Action
    public let expected: ServiceDefinition
    public let updated: ServiceDefinition?

    public init(action: Action, expected: ServiceDefinition, updated: ServiceDefinition? = nil) {
        self.action = action
        self.expected = expected
        self.updated = updated
    }
}

public struct DaemonOperationResult: Codable, Sendable {
    public var error: MoyError?
    public init(error: MoyError? = nil) {
        self.error = error
    }
}
