public enum ServiceKind: String, Codable, CaseIterable, Equatable, Sendable {
    case launchAgent
    case launchDaemon
}
