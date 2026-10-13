public enum ServiceIdentifierValidationIssue: CaseIterable, Equatable, Sendable {
    case empty
    case tooLong
    case invalidCharacters
    case invalidBoundary
}
