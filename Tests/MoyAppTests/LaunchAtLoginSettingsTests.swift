@testable import MoyApp
import MoyKit
import Testing

@Suite("Launch at login settings")
struct LaunchAtLoginSettingsTests {
    @Test(arguments: [LaunchAtLoginStatus.notRegistered, .enabled, .requiresApproval, .notFound])
    func `refresh reads OS state and blocks overlapping operations`(status: LaunchAtLoginStatus) async throws {
        let useCase = TestLaunchAtLoginUseCase(currentStatus: status)
        let reducer = makeReducer(useCase)
        var state = SettingsState()
        #expect(state.launchAtLoginStatus == nil)
        #expect(await reducer.reduce(
            into: &state, action: .launchAtLogin(.setEnabled(true)),
        ).executeForTesting() == nil)
        let refresh = reducer.reduce(into: &state, action: .launchAtLogin(.refreshStatus))
        #expect(state.isCheckingLaunchAtLogin)
        #expect(await reducer.reduce(into: &state, action: .launchAtLogin(.refreshStatus)).executeForTesting() == nil)
        #expect(await reducer.reduce(
            into: &state, action: .launchAtLogin(.setEnabled(true)),
        ).executeForTesting() == nil)
        _ = try reducer.reduce(into: &state, action: #require(await refresh.executeForTesting()))
        #expect(state.launchAtLoginStatus == status)
        #expect(!state.isCheckingLaunchAtLogin)
        #expect(await useCase.updateCount == 0)
    }

    @Test(arguments: [LaunchAtLoginStatus.enabled, .requiresApproval, .notFound])
    func `enable reads actual status and blocks duplicate updates`(result: LaunchAtLoginStatus) async throws {
        let useCase = TestLaunchAtLoginUseCase(currentStatus: .notRegistered, updateStatus: result)
        let reducer = makeReducer(useCase)
        var state = SettingsState()
        state.launchAtLoginStatus = .notRegistered
        let update = reducer.reduce(into: &state, action: .launchAtLogin(.setEnabled(true)))
        #expect(state.isUpdatingLaunchAtLogin)
        #expect(state.launchAtLoginStatus == .notRegistered)
        #expect(await reducer.reduce(
            into: &state, action: .launchAtLogin(.setEnabled(true)),
        ).executeForTesting() == nil)
        #expect(await reducer.reduce(into: &state, action: .launchAtLogin(.refreshStatus)).executeForTesting() == nil)
        _ = try reducer.reduce(into: &state, action: #require(await update.executeForTesting()))
        #expect(state.launchAtLoginStatus == result)
        #expect(!state.isUpdatingLaunchAtLogin)
        #expect(state.failure == nil)
        #expect(await useCase.updateCount == 1)
        #expect(await useCase.requestedEnabled == true)
    }

    @Test(arguments: [LaunchAtLoginStatus.enabled, .requiresApproval])
    func `disable unregisters enabled and pending login items`(initial: LaunchAtLoginStatus) async throws {
        let useCase = TestLaunchAtLoginUseCase(currentStatus: initial)
        let reducer = makeReducer(useCase)
        var state = SettingsState()
        state.launchAtLoginStatus = initial
        #expect(await reducer.reduce(
            into: &state, action: .launchAtLogin(.setEnabled(true)),
        ).executeForTesting() == nil)
        let update = reducer.reduce(into: &state, action: .launchAtLogin(.setEnabled(false)))
        _ = try reducer.reduce(into: &state, action: #require(await update.executeForTesting()))
        #expect(state.launchAtLoginStatus == .notRegistered)
        #expect(await useCase.requestedEnabled == false)
        #expect(await useCase.updateCount == 1)
    }

    @Test
    func `failed update preserves OS status and error details and allows retry`() async throws {
        let useCase = TestLaunchAtLoginUseCase(
            currentStatus: .enabled, updateStatus: .requiresApproval,
            failure: .updateFailed("Operation denied"),
        )
        let reducer = makeReducer(useCase)
        var state = SettingsState()
        state.launchAtLoginStatus = .enabled
        let update = reducer.reduce(into: &state, action: .launchAtLogin(.setEnabled(false)))
        _ = try reducer.reduce(into: &state, action: #require(await update.executeForTesting()))
        #expect(state.launchAtLoginStatus == .requiresApproval)
        #expect(state.failure == .launchAtLoginFailed("Operation denied"))
        #expect(state.failure?.localizedMessage.contains("Operation denied") == true)
        #expect(!state.isUpdatingLaunchAtLogin)
        _ = reducer.reduce(into: &state, action: .dismissFailure)
        #expect(state.failure == nil)
        _ = reducer.reduce(into: &state, action: .launchAtLogin(.setEnabled(false)))
        #expect(state.isUpdatingLaunchAtLogin)
    }

    @Test
    func `system settings action opens login items and refresh reflects external changes`() async throws {
        let useCase = TestLaunchAtLoginUseCase(currentStatus: .requiresApproval)
        let reducer = makeReducer(useCase)
        var state = SettingsState()
        state.launchAtLoginStatus = .requiresApproval
        let open = reducer.reduce(into: &state, action: .launchAtLogin(.openSystemSettings))
        let refresh = try reducer.reduce(into: &state, action: #require(await open.executeForTesting()))
        _ = try reducer.reduce(into: &state, action: #require(await refresh.executeForTesting()))
        #expect(await useCase.openCount == 1)
        await useCase.setStatus(.enabled)
        let recheck = reducer.reduce(into: &state, action: .launchAtLogin(.refreshStatus))
        _ = try reducer.reduce(into: &state, action: #require(await recheck.executeForTesting()))
        #expect(state.launchAtLoginStatus == .enabled)
        #expect(await useCase.updateCount == 0)
    }

    private func makeReducer(_ useCase: TestLaunchAtLoginUseCase) -> SettingsReducer {
        SettingsReducer(dependencies: SettingsDependencies(
            launchAtLoginUseCase: useCase,
            cliInstallerClient: CLIInstallerClient(status: { .notInstalled }, install: {}, uninstall: {}),
        ))
    }
}

private actor TestLaunchAtLoginUseCase: LaunchAtLoginUseCase {
    var currentStatus: LaunchAtLoginStatus
    var updateStatus: LaunchAtLoginStatus?
    var failure: LaunchAtLoginError?
    var updateCount = 0
    var requestedEnabled: Bool?
    var openCount = 0

    init(currentStatus: LaunchAtLoginStatus, updateStatus: LaunchAtLoginStatus? = nil,
         failure: LaunchAtLoginError? = nil)
    {
        self.currentStatus = currentStatus
        self.updateStatus = updateStatus
        self.failure = failure
    }

    func status() -> LaunchAtLoginStatus {
        currentStatus
    }

    func setStatus(_ status: LaunchAtLoginStatus) {
        currentStatus = status
    }

    func setEnabled(_ enabled: Bool) throws {
        updateCount += 1
        requestedEnabled = enabled
        currentStatus = updateStatus ?? (enabled ? .enabled : .notRegistered)
        if let failure {
            throw failure
        }
    }

    func openSystemSettings() {
        openCount += 1
    }
}
