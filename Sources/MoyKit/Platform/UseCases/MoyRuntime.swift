import Darwin
import Foundation

public enum MoyRuntime {
    public static func makeServiceTransferUseCase(paths: MoyPaths = .defaults()) -> any ServiceTransferUseCase {
        DefaultServiceTransferUseCase(
            serviceManagementUseCase: makeServiceManagementUseCase(paths: paths), paths: paths,
        )
    }

    public static func makeServiceManagementUseCase(paths: MoyPaths = .defaults()) -> any ServiceManagementUseCase {
        makeServiceManagementUseCase(paths: paths, userID: nil, repository: JSONServiceRepository(paths: paths))
    }

    public static func makeServiceManagementUseCase(
        paths: MoyPaths, userID: UInt32?, repository: any ServiceRepository,
        launchAgentRepository: (any LaunchdRepository)? = nil,
        daemonLogRepository: (any ServiceLogRepository)? = nil,
    ) -> any ServiceManagementUseCase {
        DefaultServiceManagementUseCase(
            serviceRepository: repository,
            launchAgentRepository: launchAgentRepository ?? LaunchctlServiceRepository(
                paths: paths, userID: userID ?? getuid(),
            ),
            launchDaemonRepository: LaunchctlServiceRepository(
                paths: paths, kind: .launchDaemon,
                logRepository: daemonLogRepository ?? LocalServiceLogRepository(),
            ),
        )
    }
}
