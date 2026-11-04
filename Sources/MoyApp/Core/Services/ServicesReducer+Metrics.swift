import Foundation
import MoyKit
import NanoRedux

extension ServicesReducer {
    private static let metricsRefreshEffectID = "services.metrics.refresh"

    func reduceMetrics(
        into state: inout ServicesState, action: ServicesMetricsAction,
    ) -> Effect<ServicesAction> {
        switch action {
        case let .setVisibility(identifier, isVisible):
            let wasVisible = hasMetricsPresentation(state)
            if isVisible {
                guard state.selectedIdentifier == identifier,
                      state.services.contains(where: { $0.identifier == identifier }),
                      state.metrics.visibleIdentifier != identifier
                else { return .none }
                state.metrics.visibleIdentifier = identifier
            } else {
                guard state.metrics.visibleIdentifier == identifier else { return .none }
                state.metrics.visibleIdentifier = nil
            }
            return .merge {
                synchronizeMetrics(into: &state)
                refreshMetricsStatus(wasVisible: wasVisible, isVisible: hasMetricsPresentation(state))
            }

        case let .setMenuVisibility(isVisible):
            guard state.metrics.isMenuVisible != isVisible else { return .none }
            let wasVisible = hasMetricsPresentation(state)
            state.metrics.isMenuVisible = isVisible
            return .merge {
                synchronizeMetrics(into: &state)
                refreshMetricsStatus(wasVisible: wasVisible, isVisible: hasMetricsPresentation(state))
            }

        case let .receive(sessionID, event):
            return receiveMetrics(into: &state, sessionID: sessionID, event: event)
        }
    }

    func synchronizeMetrics(into state: inout ServicesState) -> Effect<ServicesAction> {
        var pids: Set<Int32> = []
        if state.metrics.isMenuVisible {
            for service in state.services {
                if let pid = metricsPID(for: service.identifier, state: state) {
                    pids.insert(pid)
                }
            }
        }
        let detailIdentifier = state.metrics.visibleIdentifier
        let detailPID = detailIdentifier.flatMap { identifier in
            state.selectedIdentifier == identifier ? metricsPID(for: identifier, state: state) : nil
        }
        if let detailPID {
            pids.insert(detailPID)
        }
        var effects: [Effect<ServicesAction>] = []
        for pid in Set(state.metrics.processes.keys).subtracting(pids).sorted() {
            state.metrics.processes.removeValue(forKey: pid)
            effects.append(.run(lifetime: .replaceable(Self.metricsEffectID(pid))) { nil })
        }
        let events = dependencies.metricsClient.events
        for pid in pids.subtracting(state.metrics.processes.keys).sorted() {
            let process = ServicesProcessMetricsState(id: UUID(), pid: pid)
            state.metrics.processes[pid] = process
            effects.append(.stream(lifetime: .replaceable(Self.metricsEffectID(pid))) {
                events(pid).map { ServicesAction.metrics(.receive(process.id, $0)) }
            })
        }
        synchronizeDetailMetrics(into: &state, identifier: detailIdentifier, pid: detailPID)
        return .merge {
            for effect in effects {
                effect
            }
        }
    }

    private func receiveMetrics(
        into state: inout ServicesState, sessionID: UUID, event: ServicesMetricsEvent,
    ) -> Effect<ServicesAction> {
        guard let pid = state.metrics.processes.first(where: { $0.value.id == sessionID })?.key,
              var process = state.metrics.processes[pid]
        else { return .none }
        switch event {
        case let .capacity(bytes):
            state.metrics.physicalMemory = bytes > 0 ? bytes : nil
            return .none
        case let .sample(sample):
            guard sample.pid == pid else { return .none }
            process.sample = sample
            process.isUnavailable = false
            state.metrics.processes[pid] = process
            if state.metrics.session?.id == sessionID {
                state.metrics.sample = sample
                state.metrics.isUnavailable = false
                state.metrics.history.append(sample)
            }
            return .none
        case .ended, .failed:
            process.sample = nil
            process.isUnavailable = true
            state.metrics.processes[pid] = process
            if state.metrics.session?.id == sessionID {
                state.metrics.sample = nil
                state.metrics.history = .init()
                state.metrics.isUnavailable = true
            }
            if case .ended = event {
                return .run { .refreshServices }
            }
            return .none
        }
    }

    private func synchronizeDetailMetrics(
        into state: inout ServicesState, identifier: ServiceIdentifier?, pid: Int32?,
    ) {
        let session: ServicesMetricsSession? = if let identifier, let pid, let process = state.metrics.processes[pid] {
            .init(id: process.id, identifier: identifier, pid: pid)
        } else {
            nil
        }
        guard state.metrics.session != session else { return }
        state.metrics.session = session
        state.metrics.history = .init()
        state.metrics.sample = pid.flatMap { state.metrics.processes[$0]?.sample }
        state.metrics.isUnavailable = pid.flatMap { state.metrics.processes[$0]?.isUnavailable } ?? false
        if let sample = state.metrics.sample {
            state.metrics.history.append(sample)
        }
    }

    private func metricsPID(for identifier: ServiceIdentifier, state: ServicesState) -> Int32? {
        guard !state.statusFailures.contains(identifier), !state.isOperating(identifier) else { return nil }
        return state.statuses[identifier]?.metricsPID
    }

    private func hasMetricsPresentation(_ state: ServicesState) -> Bool {
        state.metrics.isMenuVisible || state.metrics.visibleIdentifier != nil
    }

    private func refreshMetricsStatus(wasVisible: Bool, isVisible: Bool) -> Effect<ServicesAction> {
        guard wasVisible != isVisible else { return .none }
        guard isVisible else {
            return .run(lifetime: .replaceable(Self.metricsRefreshEffectID)) { nil }
        }
        let refreshTicks = dependencies.metricsClient.refreshTicks
        return .stream(lifetime: .replaceable(Self.metricsRefreshEffectID)) {
            refreshTicks().map { _ in ServicesAction.refreshServices }
        }
    }

    private static func metricsEffectID(_ pid: Int32) -> String {
        "services.metrics.\(pid)"
    }
}
