import Foundation
import NanoRedux

extension ServicesReducer {
    private static let metricsEffectID = "services.metrics"
    private static let metricsRefreshEffectID = "services.metrics.refresh"

    func reduceMetrics(
        into state: inout ServicesState, action: ServicesMetricsAction,
    ) -> Effect<ServicesAction> {
        switch action {
        case let .setVisibility(identifier, isVisible):
            if isVisible {
                guard state.selectedIdentifier == identifier,
                      state.services.contains(where: { $0.identifier == identifier }),
                      state.metrics.visibleIdentifier != identifier
                else { return .none }
                state.metrics.visibleIdentifier = identifier
                let refreshTicks = dependencies.metricsClient.refreshTicks
                return .merge {
                    synchronizeMetrics(into: &state)
                    Effect<ServicesAction>.stream(lifetime: .replaceable(Self.metricsRefreshEffectID)) {
                        refreshTicks().map { _ in ServicesAction.refreshServices }
                    }
                }
            }
            guard state.metrics.visibleIdentifier == identifier else { return .none }
            state.metrics.visibleIdentifier = nil
            return .merge {
                synchronizeMetrics(into: &state)
                Effect<ServicesAction>.run(lifetime: .replaceable(Self.metricsRefreshEffectID)) { nil }
            }

        case let .receive(sessionID, event):
            return receiveMetrics(into: &state, sessionID: sessionID, event: event)
        }
    }

    private func receiveMetrics(
        into state: inout ServicesState, sessionID: UUID, event: ServicesMetricsEvent,
    ) -> Effect<ServicesAction> {
        guard let session = state.metrics.session, session.id == sessionID,
              state.metrics.visibleIdentifier == session.identifier,
              state.selectedIdentifier == session.identifier
        else { return .none }
        switch event {
        case let .capacity(bytes):
            state.metrics.physicalMemory = bytes > 0 ? bytes : nil
            return .none
        case let .sample(sample):
            guard sample.pid == session.pid else { return .none }
            state.metrics.sample = sample
            state.metrics.history.append(sample)
            state.metrics.isUnavailable = false
            return .none
        case .ended:
            state.metrics.sample = nil
            state.metrics.history = .init()
            state.metrics.isUnavailable = true
            return .run { .refreshServices }
        case .failed:
            state.metrics.sample = nil
            state.metrics.history = .init()
            state.metrics.isUnavailable = true
            return .none
        }
    }

    func synchronizeMetrics(into state: inout ServicesState) -> Effect<ServicesAction> {
        let identifier = state.metrics.visibleIdentifier
        let pid = identifier.flatMap { identifier in
            guard state.selectedIdentifier == identifier,
                  !state.statusFailures.contains(identifier),
                  !state.isOperating(identifier)
            else { return nil as Int32? }
            return state.statuses[identifier]?.metricsPID
        }
        guard let identifier, let pid else {
            guard state.metrics.session != nil else { return .none }
            state.metrics.session = nil
            state.metrics.sample = nil
            state.metrics.history = .init()
            state.metrics.isUnavailable = false
            return .run(lifetime: .replaceable(Self.metricsEffectID)) { nil }
        }
        if let session = state.metrics.session, session.identifier == identifier, session.pid == pid {
            return .none
        }
        let session = ServicesMetricsSession(id: UUID(), identifier: identifier, pid: pid)
        state.metrics.session = session
        state.metrics.sample = nil
        state.metrics.history = .init()
        state.metrics.isUnavailable = false
        let events = dependencies.metricsClient.events
        return .stream(lifetime: .replaceable(Self.metricsEffectID)) {
            events(pid).map { ServicesAction.metrics(.receive(session.id, $0)) }
        }
    }
}
