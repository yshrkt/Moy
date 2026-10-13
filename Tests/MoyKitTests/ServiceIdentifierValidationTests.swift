import Foundation
@testable import MoyKit
import Testing

struct ServiceIdentifierValidationTests {
    @Test(arguments: [
        ("", ServiceIdentifierValidationIssue.empty),
        (String(repeating: "a", count: 65), .tooLong),
        ("API", .invalidCharacters),
        ("api server", .invalidCharacters),
        ("api.server", .invalidCharacters),
        ("サービス", .invalidCharacters),
        (" api", .invalidCharacters),
        ("api\n", .invalidCharacters),
        ("-api", .invalidBoundary),
        ("api_", .invalidBoundary),
        ("_", .invalidBoundary),
    ])
    func `invalid identifiers have a reason and remain rejected by the domain`(
        value: String,
        issue: ServiceIdentifierValidationIssue,
    ) {
        #expect(ServiceIdentifier.validationIssue(for: value) == issue)
        #expect(!ServiceIdentifier.isValid(value))
        #expect(throws: MoyError.invalidIdentifier(value)) {
            try ServiceIdentifier(value)
        }
    }

    @Test(arguments: ["a", "0", "api-server_2", String(repeating: "a", count: 64)])
    func `valid identifiers retain their exact value`(value: String) throws {
        #expect(ServiceIdentifier.validationIssue(for: value) == nil)
        #expect(ServiceIdentifier.isValid(value))
        #expect(try ServiceIdentifier(value).rawValue == value)
    }
}
