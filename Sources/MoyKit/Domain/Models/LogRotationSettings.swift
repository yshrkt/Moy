import Foundation

public struct LogRotationSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var maximumSizeMB: Int
    public var generations: Int

    public init(isEnabled: Bool = false, maximumSizeMB: Int = 10, generations: Int = 5) {
        self.isEnabled = isEnabled
        self.maximumSizeMB = maximumSizeMB
        self.generations = generations
    }

    public func validate() throws {
        guard (1 ... 100_000).contains(maximumSizeMB), (1 ... 100).contains(generations) else {
            throw LogRotationError.invalidSettings
        }
    }
}

public enum LogRotationError: Error, Equatable, Sendable {
    case jobStateUnavailable(String)
    case jobUpdateFailed(LogRotationSettings, String)
    case invalidSettings
    case jobConflict(String)
    case files([String])
}

extension LogRotationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidSettings: "Invalid log rotation settings."
        case let .jobConflict(path): "Conflicting log rotation job: \(path)"
        case let .files(failures): failures.joined(separator: "\n")
        case let .jobUpdateFailed(_, reason): reason
        case let .jobStateUnavailable(reason): reason
        }
    }
}
