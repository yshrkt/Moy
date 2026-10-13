import MoyKit

enum ServiceEditorIdentifierIssue: Equatable, Sendable {
    case invalidFormat(ServiceIdentifierValidationIssue)
    case duplicate
}
