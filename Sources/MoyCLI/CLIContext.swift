import Darwin
import Foundation
import MoyKit

enum CLIContext {
    static var transfer: any ServiceTransferUseCase {
        get throws {
            let user = try MoyUserContext.resolve()
            let documents: any ServiceDocumentRepository = try geteuid() == 0
                ? UserServiceRepository(userID: user.userID, executable: executablePath())
                : JSONServiceDocumentRepository()
            return try DefaultServiceTransferUseCase(
                serviceManagementUseCase: services, documentRepository: documents, paths: user.paths,
            )
        }
    }

    static var services: any ServiceManagementUseCase {
        get throws { try services(user: MoyUserContext.resolve()) }
    }

    static func services(user: MoyUserContext) throws -> any ServiceManagementUseCase {
        let repository: any ServiceRepository = try geteuid() == 0
            ? UserServiceRepository(userID: user.userID, executable: executablePath())
            : JSONServiceRepository(paths: user.paths)
        let agent: (any LaunchdRepository)? = try geteuid() == 0
            ? UserServiceRepository(userID: user.userID, executable: executablePath()) : nil
        return MoyRuntime.makeServiceManagementUseCase(
            paths: user.paths, userID: user.userID, repository: repository, launchAgentRepository: agent,
        )
    }

    static func executablePath() throws -> String {
        guard let url = Bundle.main.executableURL else { throw MoyError.operationFailed("CLI executable not found") }
        return url.resolvingSymlinksInPath().path
    }
}
