import MoyKit

enum CLIContext {
    static var transfer: any ServiceTransferUseCase {
        MoyRuntime.makeServiceTransferUseCase()
    }

    static var services: any ServiceManagementUseCase {
        MoyRuntime.makeServiceManagementUseCase()
    }
}
