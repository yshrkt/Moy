import Foundation
@testable import MoyKit
import Testing

struct ServiceValidationTests {
    @Test(arguments: ServiceValidationIssue.allCases)
    func `validator returns each typed reason`(issue: ServiceValidationIssue) throws {
        var service = try fixtureService()
        switch issue {
        case .blankDisplayName: service.displayName = " \n"
        case .missingExecutable: service.programArguments = []
        case .relativeExecutable: service.programArguments = ["printf"]
        case .relativeWorkingDirectory: service.workingDirectory = "relative"
        case .invalidThrottleInterval: service.throttleInterval = 0
        case .invalidStandardOutPath: service.standardOutPath = ""
        case .invalidStandardErrorPath: service.standardErrorPath = "relative"
        case .invalidEnvironmentName: service.environmentVariables = ["INVALID=NAME": "value"]
        }
        #expect(throws: MoyError.invalidService([issue])) {
            try ServiceValidator.validate(service)
        }
    }

    @Test
    func `validator preserves multiple reasons`() throws {
        var service = try fixtureService()
        service.programArguments = [""]
        service.standardOutPath = "relative"
        service.environmentVariables = ["": "value"]
        #expect(throws: MoyError.invalidService([
            .missingExecutable, .invalidStandardOutPath, .invalidEnvironmentName,
        ])) {
            try ServiceValidator.validate(service)
        }
    }
}
