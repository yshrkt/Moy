import ServiceManagement

public struct DefaultLaunchAtLoginUseCase: LaunchAtLoginUseCase {
    public init() {}

    public func status() async -> LaunchAtLoginStatus {
        await MainActor.run {
            switch SMAppService.mainApp.status {
            case .notRegistered: .notRegistered
            case .enabled: .enabled
            case .requiresApproval: .requiresApproval
            case .notFound: .notFound
            @unknown default: .notFound
            }
        }
    }

    public func setEnabled(_ enabled: Bool) async throws {
        try await MainActor.run {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                throw LaunchAtLoginError.updateFailed(error.localizedDescription)
            }
        }
    }

    public func openSystemSettings() async {
        await MainActor.run { SMAppService.openSystemSettingsLoginItems() }
    }
}
