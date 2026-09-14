import MoyKit

enum CLIContext {
    static var services: any ServiceManagementUseCase {
        MoyRuntime.makeServiceManagementUseCase()
    }
}
