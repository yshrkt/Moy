@testable import MoyApp
import Testing

@Suite("Settings reducer")
struct SettingsReducerTests {
    @Test
    func `read installation status on each appearance`() async throws {
        let client = TestCLIInstallerClient()
        let reducer = makeReducer(client)
        var state = SettingsState()

        let first = reducer.reduce(into: &state, action: .appear)
        #expect(state.isCheckingCLI)
        _ = try reducer.reduce(into: &state, action: #require(await first.executeForTesting()))
        #expect(state.cliStatus == .installed)

        await client.setStatus(.notInstalled)
        let second = reducer.reduce(into: &state, action: .appear)
        _ = try reducer.reduce(into: &state, action: #require(await second.executeForTesting()))
        #expect(state.cliStatus == .notInstalled)
        #expect(!state.isCheckingCLI)
    }

    @Test
    func `install prevents duplicate and overlapping checks`() async throws {
        let client = TestCLIInstallerClient()
        let reducer = makeReducer(client)
        var state = SettingsState()
        state.cliStatus = .notInstalled

        let install = reducer.reduce(into: &state, action: .installCLI)
        #expect(state.isInstallingCLI)
        let duplicate = reducer.reduce(into: &state, action: .installCLI)
        let refresh = reducer.reduce(into: &state, action: .refreshCLIStatus)
        #expect(await duplicate.executeForTesting() == nil)
        #expect(await refresh.executeForTesting() == nil)
        _ = try reducer.reduce(into: &state, action: #require(await install.executeForTesting()))
        #expect(await client.installCount == 1)
        #expect(state.cliStatus == .installed)
        #expect(!state.isInstallingCLI)
    }

    @Test
    func `installation failure refreshes actual state and remains visible`() async throws {
        let client = TestCLIInstallerClient()
        await client.setInstallFailure(.cliDestinationExists)
        await client.setStatus(.conflict)
        let reducer = makeReducer(client)
        var state = SettingsState()
        state.cliStatus = .notInstalled

        let install = reducer.reduce(into: &state, action: .installCLI)
        let refresh = try reducer.reduce(into: &state, action: #require(await install.executeForTesting()))
        #expect(!state.isInstallingCLI)
        #expect(state.failure == .cliDestinationExists)
        let check = try reducer.reduce(into: &state, action: #require(await refresh.executeForTesting()))
        _ = try reducer.reduce(into: &state, action: #require(await check.executeForTesting()))
        #expect(state.cliStatus == .conflict)
        #expect(state.failure == .cliDestinationExists)
        _ = reducer.reduce(into: &state, action: .dismissFailure)
        #expect(state.failure == nil)
    }

    @Test
    func `cancel authentication without showing an error and allow retry`() async throws {
        let reducer = SettingsReducer(dependencies: SettingsDependencies(
            cliInstallerClient: CLIInstallerClient(
                status: { .notInstalled },
                install: { throw CancellationError() },
                uninstall: {},
            ),
        ))
        var state = SettingsState()
        state.cliStatus = .notInstalled
        let install = reducer.reduce(into: &state, action: .installCLI)
        let refresh = try reducer.reduce(into: &state, action: #require(await install.executeForTesting()))
        #expect(!state.isInstallingCLI)
        #expect(state.failure == nil)
        let check = try reducer.reduce(into: &state, action: #require(await refresh.executeForTesting()))
        _ = try reducer.reduce(into: &state, action: #require(await check.executeForTesting()))
        #expect(state.cliStatus == .notInstalled)
        _ = reducer.reduce(into: &state, action: .installCLI)
        #expect(state.isInstallingCLI)
    }

    @Test
    func `status failure does not retain installed state`() async throws {
        let reducer = SettingsReducer(dependencies: SettingsDependencies(
            cliInstallerClient: CLIInstallerClient(
                status: { throw SettingsFailure.unexpected("Permission denied") },
                install: {},
                uninstall: {},
            ),
        ))
        var state = SettingsState()
        state.cliStatus = .installed
        let check = reducer.reduce(into: &state, action: .appear)
        _ = try reducer.reduce(into: &state, action: #require(await check.executeForTesting()))
        #expect(state.cliStatus == nil)
        #expect(!state.isCheckingCLI)
        #expect(state.failure == .unexpected("Permission denied"))
    }

    @Test(arguments: ["success", "cancel", "failure"])
    func `uninstall requires confirmation and refreshes after cancellation or failure`(outcome: String) async throws {
        let reducer = SettingsReducer(dependencies: SettingsDependencies(cliInstallerClient: CLIInstallerClient(
            status: { outcome == "failure" ? .conflict : .installed }, install: {}, uninstall: {
                if outcome == "cancel" {
                    throw CancellationError()
                }
                if outcome == "failure" {
                    throw SettingsFailure.cliLinkChanged
                }
            },
        )))
        var state = SettingsState()
        state.cliStatus = .installed
        #expect(await reducer.reduce(into: &state, action: .uninstallCLI).executeForTesting() == nil)
        _ = reducer.reduce(into: &state, action: .requestCLIUninstallation)
        #expect(state.isConfirmingCLIUninstallation)
        _ = reducer.reduce(into: &state, action: .dismissCLIUninstallation)
        #expect(!state.isConfirmingCLIUninstallation)
        _ = reducer.reduce(into: &state, action: .requestCLIUninstallation)
        let uninstall = reducer.reduce(into: &state, action: .uninstallCLI)
        #expect(state.isUninstallingCLI)
        #expect(!state.isConfirmingCLIUninstallation)
        #expect(await reducer.reduce(into: &state, action: .refreshCLIStatus).executeForTesting() == nil)
        #expect(await reducer.reduce(into: &state, action: .uninstallCLI).executeForTesting() == nil)
        let followup = try reducer.reduce(into: &state, action: #require(await uninstall.executeForTesting()))
        #expect(!state.isUninstallingCLI)
        if outcome == "success" {
            #expect(state.cliStatus == .notInstalled)
        } else {
            let check = try reducer.reduce(into: &state, action: #require(await followup.executeForTesting()))
            _ = try reducer.reduce(into: &state, action: #require(await check.executeForTesting()))
            #expect(state.cliStatus == (outcome == "failure" ? .conflict : .installed))
        }
        #expect(state.failure == (outcome == "failure" ? .cliLinkChanged : nil))
    }

    @Test
    func `conflict reveals installation destination and prevents uninstall`() async throws {
        let reducer = SettingsReducer(dependencies: SettingsDependencies(
            cliInstallerClient: CLIInstallerClient(
                status: { .conflict },
                install: {},
                uninstall: { Issue.record("Must not uninstall a conflict") },
            ),
            workspaceClient: WorkspaceClient(
                open: { _ in },
                reveal: { path in #expect(path == CLIInstaller.installationPath) },
            ),
        ))
        var state = SettingsState()
        state.cliStatus = .conflict
        _ = reducer.reduce(into: &state, action: .requestCLIUninstallation)
        #expect(!state.isConfirmingCLIUninstallation)
        #expect(await reducer.reduce(into: &state, action: .uninstallCLI).executeForTesting() == nil)
        let reveal = reducer.reduce(into: &state, action: .revealCLI)
        _ = try reducer.reduce(into: &state, action: #require(await reveal.executeForTesting()))
        #expect(state.failure == nil)
    }

    private func makeReducer(_ client: TestCLIInstallerClient) -> SettingsReducer {
        SettingsReducer(dependencies: SettingsDependencies(
            cliInstallerClient: CLIInstallerClient(
                status: { await client.status },
                install: { try await client.install() },
                uninstall: {},
            ),
        ))
    }
}

private actor TestCLIInstallerClient {
    var status: CLIInstallationStatus = .installed
    var installCount = 0
    private var failure: SettingsFailure?

    func setStatus(_ status: CLIInstallationStatus) {
        self.status = status
    }

    func setInstallFailure(_ failure: SettingsFailure) {
        self.failure = failure
    }

    func install() throws {
        installCount += 1
        if let failure {
            throw failure
        }
    }
}
