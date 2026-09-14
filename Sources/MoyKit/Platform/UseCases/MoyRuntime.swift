public enum MoyRuntime {
    public static func makeServiceManagementUseCase(paths: MoyPaths = .defaults()) -> any ServiceManagementUseCase {
        DefaultServiceManagementUseCase(
            serviceRepository: JSONServiceRepository(paths: paths),
            launchAgentRepository: LaunchctlAgentRepository(paths: paths),
        )
    }
}
