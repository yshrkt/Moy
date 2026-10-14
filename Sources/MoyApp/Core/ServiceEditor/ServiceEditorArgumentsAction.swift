import Foundation

enum ServiceEditorArgumentsAction: Sendable {
    case selectArgument(UUID?)
    case moveArgument(UUID, toIndex: Int)
    case dropArgument(UUID, insertionIndex: Int)
    case addArgument
    case updateArgument(UUID, String)
    case removeArgument(UUID)
}
