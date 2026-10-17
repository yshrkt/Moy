import Foundation

enum ServiceEditorEnvironmentAction: Sendable {
    case select(UUID?)
    case add
    case updateKey(UUID, String)
    case updateValue(UUID, String)
    case remove(UUID)
}
