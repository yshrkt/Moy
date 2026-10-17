import Foundation

enum ServiceEditorArgumentsAction: Sendable {
    case select(UUID?)
    case move(UUID, toIndex: Int)
    case drop(UUID, insertionIndex: Int)
    case add
    case update(UUID, String)
    case remove(UUID)
}
