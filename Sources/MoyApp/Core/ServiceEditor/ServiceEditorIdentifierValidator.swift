import MoyKit

enum ServiceEditorIdentifierValidator {
    static func validate(_ identifier: String, existingIdentifiers: Set<String>) -> ServiceEditorIdentifierIssue? {
        if let issue = ServiceIdentifierValidator.validate(identifier) {
            return .invalidFormat(issue)
        }
        return existingIdentifiers.contains(identifier) ? .duplicate : nil
    }
}
