import Foundation

private enum RuntimeCodingKeys: String, CodingKey {
    case state
    case pid
}

private enum RuntimeCodingState: String, Codable {
    case notLoaded
    case waiting
    case running
}

public struct ServiceStatus: Codable, Equatable, Sendable {
    public enum Registration: String, Codable, Equatable, Sendable {
        case disabled
        case enabled
        case plistOnly
        case loadedOnly
    }

    public enum Runtime: Codable, Equatable, Sendable {
        case notLoaded
        case waiting
        case running(pid: Int32)

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: RuntimeCodingKeys.self)
            switch try container.decode(RuntimeCodingState.self, forKey: .state) {
            case .notLoaded:
                self = .notLoaded
            case .waiting:
                self = .waiting
            case .running:
                self = try .running(pid: container.decode(Int32.self, forKey: .pid))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: RuntimeCodingKeys.self)
            switch self {
            case .notLoaded:
                try container.encode(RuntimeCodingState.notLoaded, forKey: .state)
            case .waiting:
                try container.encode(RuntimeCodingState.waiting, forKey: .state)
            case let .running(pid):
                try container.encode(RuntimeCodingState.running, forKey: .state)
                try container.encode(pid, forKey: .pid)
            }
        }
    }

    public let identifier: ServiceIdentifier
    public let registration: Registration
    public let runtime: Runtime
    public let lastExitStatus: Int32?

    public init(
        identifier: ServiceIdentifier,
        registration: Registration,
        runtime: Runtime,
        lastExitStatus: Int32? = nil,
    ) {
        self.identifier = identifier
        self.registration = registration
        self.runtime = runtime
        self.lastExitStatus = lastExitStatus
    }
}
