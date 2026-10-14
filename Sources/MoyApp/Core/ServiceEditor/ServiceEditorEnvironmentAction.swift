import Foundation

enum ServiceEditorEnvironmentAction: Sendable {
    case selectEnvironmentVariable(UUID?)
    case addEnvironmentVariable
    case updateEnvironmentKey(UUID, String)
    case updateEnvironmentValue(UUID, String)
    case removeEnvironmentVariable(UUID)
}
