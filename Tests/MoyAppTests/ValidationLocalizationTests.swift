import Foundation
@testable import MoyApp
import MoyKit
import Testing

struct ValidationLocalizationTests {
    @Test(arguments: ServiceIdentifierValidationIssue.allCases)
    func `identifier reasons have Japanese and English messages`(issue: ServiceIdentifierValidationIssue) throws {
        let key = "validation.identifier.\(issue)"
        try expectIdentifierTranslations(key: key, localizedMessage: issue.localizedMessage)
    }

    @Test
    func `identifier duplicates have Japanese and English messages`() throws {
        try expectIdentifierTranslations(
            key: "validation.identifier.duplicate",
            localizedMessage: ServiceEditorIdentifierIssue.duplicate.localizedMessage,
        )
    }

    private func expectIdentifierTranslations(key: String, localizedMessage: String) throws {
        let bundle = MoyResources.bundle
        for language in ["ja", "en"] {
            let path = try #require(bundle.path(forResource: language, ofType: "lproj"))
            let languageBundle = try #require(Bundle(path: path))
            #expect(languageBundle.localizedString(forKey: key, value: nil, table: "Localizable") != key)
        }
        #expect(localizedMessage == bundle.localizedString(forKey: key, value: nil, table: "Localizable"))
    }

    @Test(arguments: ServiceValidationIssue.allCases)
    func `every reason has Japanese and English resources and localized GUI output`(
        issue: ServiceValidationIssue,
    ) throws {
        let key = "validation.\(issue)"
        let resourceBundle = MoyResources.bundle
        let japanesePath = try #require(resourceBundle.path(forResource: "ja", ofType: "lproj"))
        let englishPath = try #require(resourceBundle.path(forResource: "en", ofType: "lproj"))
        let japaneseBundle = try #require(Bundle(path: japanesePath))
        let englishBundle = try #require(Bundle(path: englishPath))
        let japanese = japaneseBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        let english = englishBundle.localizedString(forKey: key, value: nil, table: "Localizable")
        #expect(japanese != key)
        #expect(english != key)
        #expect(japanese != english)
        #expect(MoyError.invalidService([issue]).localizedDescription == "Invalid service configuration: \(english)")
        #expect(issue.localizedMessage == resourceBundle.localizedString(forKey: key, value: nil, table: "Localizable"))
        #expect(ServicesFailure.moy(.invalidService([issue])).localizedMessage
            == "\(L10n.Error.invalidService)\n\(issue.localizedMessage)")
    }

    @Test
    func `empty log paths in editor return typed reasons`() throws {
        let identifier = try ServiceIdentifier("validation-fixture")
        let service = ServiceDefinition(
            identifier: identifier,
            programArguments: ["/usr/bin/true"],
            standardOutPath: "/tmp/validation.out",
            standardErrorPath: "/tmp/validation.err",
        )
        let editor = ServiceEditorState(service: service)
        editor.standardOutPath = ""
        editor.standardErrorPath = " "
        #expect(throws: MoyError.invalidService([.invalidStandardOutPath, .invalidStandardErrorPath])) {
            _ = try ServiceEditorPayload(editor: editor)
        }
    }
}
