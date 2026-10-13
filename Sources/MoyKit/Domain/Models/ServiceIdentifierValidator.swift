public enum ServiceIdentifierValidator {
    public static func validate(_ value: String) -> ServiceIdentifierValidationIssue? {
        guard !value.isEmpty else { return .empty }
        guard value.count <= ServiceIdentifier.maximumLength else { return .tooLong }
        guard value.wholeMatch(of: /[a-z0-9_-]+/) != nil else { return .invalidCharacters }
        guard value.wholeMatch(of: /[a-z0-9](?:[a-z0-9_-]*[a-z0-9])?/) != nil else {
            return .invalidBoundary
        }
        return nil
    }
}
