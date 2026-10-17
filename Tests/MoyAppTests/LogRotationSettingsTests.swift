@testable import MoyApp
import MoyKit
import Testing

@Suite("Log rotation settings")
struct LogRotationSettingsTests {
    @Test
    func `refresh and update use effects and reject overlapping operations`() async throws {
        let client = TestRotationUseCase()
        let reducer = SettingsReducer(dependencies: SettingsDependencies(logRotationUseCase: client))
        var state = SettingsState()
        let refresh = reducer.reduce(into: &state, action: .logRotation(.refresh))
        #expect(state.isOperatingLogRotation)
        let duplicate = reducer.reduce(into: &state, action: .logRotation(.refresh))
        #expect(await duplicate.executeForTesting() == nil)
        _ = try reducer.reduce(into: &state, action: #require(await refresh.executeForTesting()))
        #expect(state.logRotationSettings == .init())
        let update = reducer.reduce(into: &state, action: .logRotation(.setEnabled(true)))
        let overlap = reducer.reduce(into: &state, action: .logRotation(.setGenerations(9)))
        #expect(await overlap.executeForTesting() == nil)
        _ = try reducer.reduce(into: &state, action: #require(await update.executeForTesting()))
        #expect(state.logRotationSettings?.isEnabled == true)
        #expect(state.logRotationSettings?.generations == 5)
        #expect(await client.updateCount == 1)
        #expect(!state.isOperatingLogRotation)
    }

    @Test(arguments: [true, false])
    func `failure reflects actual state and the switch can retry`(enabled: Bool) async throws {
        let client = TestRotationUseCase()
        await client.setRegistered(!enabled)
        await client.failUpdates()
        let reducer = SettingsReducer(dependencies: SettingsDependencies(logRotationUseCase: client))
        var state = SettingsState()
        state.logRotationSettings = .init(isEnabled: !enabled)
        let update = reducer.reduce(into: &state, action: .logRotation(.setEnabled(enabled)))
        _ = try reducer.reduce(into: &state, action: #require(await update.executeForTesting()))
        #expect(state.logRotationSettings?.isEnabled == !enabled)
        #expect(state.failure != nil)
        #expect(!state.isOperatingLogRotation)
        #expect(!state.isLogRotationRegistrationUnknown)
        await client.allowUpdates()
        let retry = reducer.reduce(into: &state, action: .logRotation(.setEnabled(enabled)))
        _ = try reducer.reduce(into: &state, action: #require(await retry.executeForTesting()))
        #expect(state.logRotationSettings?.isEnabled == enabled)
        #expect(!state.isOperatingLogRotation)
    }

    @Test
    func `unknown registration preserves display and blocks changes until refreshed`() async throws {
        let client = TestRotationUseCase()
        let reducer = SettingsReducer(dependencies: SettingsDependencies(logRotationUseCase: client))
        var state = SettingsState()
        state.logRotationSettings = .init(isEnabled: true)
        _ = reducer.reduce(into: &state, action: .logRotation(.receive(.failure(
            .logRotationStateUnavailable("status failed"),
        ))))
        #expect(state.logRotationSettings?.isEnabled == true)
        #expect(state.isLogRotationRegistrationUnknown)
        let toggle = reducer.reduce(into: &state, action: .logRotation(.setEnabled(false)))
        #expect(await toggle.executeForTesting() == nil)
        let refresh = reducer.reduce(into: &state, action: .logRotation(.refresh))
        _ = try reducer.reduce(into: &state, action: #require(await refresh.executeForTesting()))
        #expect(!state.isLogRotationRegistrationUnknown)
        #expect(state.logRotationSettings?.isEnabled == false)
    }
}

private actor TestRotationUseCase: LogRotationUseCase {
    var settings = LogRotationSettings()
    var updateCount = 0
    var shouldFail = false

    func failUpdates() {
        shouldFail = true
    }

    func allowUpdates() {
        shouldFail = false
    }

    func setRegistered(_ enabled: Bool) {
        settings.isEnabled = enabled
    }

    func refresh() async throws -> LogRotationStatus {
        .init(settings: settings)
    }

    func update(_ settings: LogRotationSettings) async throws -> LogRotationStatus {
        updateCount += 1
        if shouldFail {
            var actual = settings
            actual.isEnabled = self.settings.isEnabled
            self.settings = actual
            throw LogRotationError.jobUpdateFailed(actual, "test failure")
        }
        self.settings = settings
        return .init(settings: settings)
    }
}
