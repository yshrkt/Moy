public enum MoyRuntime {
    public static func makeServiceTransferUseCase(
        paths: MoyPaths = .defaults(),
    ) -> any ServiceTransferUseCase {
        DefaultServiceTransferUseCase(
            serviceManagementUseCase: makeServiceManagementUseCase(paths: paths),
            paths: paths,
        )
    }

    public static func makeServiceManagementUseCase(paths: MoyPaths = .defaults()) -> any ServiceManagementUseCase {
        DefaultServiceManagementUseCase(
            serviceRepository: JSONServiceRepository(paths: paths),
            launchAgentRepository: LaunchctlAgentRepository(paths: paths),
        )
    }
}
