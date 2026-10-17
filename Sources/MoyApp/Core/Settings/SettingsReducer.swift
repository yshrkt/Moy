import NanoRedux

struct SettingsReducer: InjectableReducer {
    let dependencies: SettingsDependencies

    func reduce(into state: inout SettingsState, action: SettingsAction) -> Effect<SettingsAction> {
        switch action {
        case let .launchAtLogin(action):
            return reduceLaunchAtLogin(into: &state, action: action)
                .map(namespace: Self.self) { .launchAtLogin($0) }
        case let .cli(action):
            return reduceCLI(into: &state, action: action)
                .map(namespace: Self.self) { .cli($0) }
        case let .logRotation(action):
            return reduceLogRotation(into: &state, action: action)
                .map(namespace: Self.self) { .logRotation($0) }
        case .appear:
            return reduce(into: &state, action: .cli(.refreshStatus))
        case let .selectTab(tab):
            state.selectedTab = tab
            return .none
        case .dismissFailure:
            state.failure = nil
            return .none
        }
    }
}
