import Foundation
import MoyMetrics

extension ServicesMetricsClient {
    static var live: Self {
        let monitor = SharedServicesMetricsMonitor()
        return Self(
            events: { pid in
                AsyncStream { continuation in
                    let id = UUID()
                    let task = Task { await monitor.subscribe(id: id, pid: pid, continuation: continuation) }
                    continuation.onTermination = { _ in
                        task.cancel()
                        Task { await monitor.unsubscribe(id: id) }
                    }
                }
            },
            refreshTicks: {
                AsyncStream { continuation in
                    let task = Task {
                        while !Task.isCancelled {
                            continuation.yield(())
                            do {
                                try await Task.sleep(for: .seconds(5))
                            } catch { break }
                        }
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
        )
    }
}

/// 利用側のPID別の購読を、1つのProcessMonitorと計測ループに集約します。
private actor SharedServicesMetricsMonitor {
    private struct Subscription {
        let pid: Int32
        let continuation: AsyncStream<ServicesMetricsEvent>.Continuation
    }

    private var subscriptions: [UUID: Subscription] = [:]
    private var monitor: ProcessMonitor?
    private var pump: Task<Void, Never>?
    private var isSynchronizing = false
    private var revision = 0

    deinit { pump?.cancel() }

    func subscribe(id: UUID, pid: Int32, continuation: AsyncStream<ServicesMetricsEvent>.Continuation) async {
        guard !Task.isCancelled else { continuation.finish(); return }
        guard pid > 0 else { continuation.yield(.failed); continuation.finish(); return }
        subscriptions[id] = Subscription(pid: pid, continuation: continuation)
        continuation.yield(.capacity(ProcessInfo.processInfo.physicalMemory))
        if monitor == nil {
            await startMonitor()
        }
        await synchronizeTargets()
    }

    func unsubscribe(id: UUID) async {
        guard subscriptions.removeValue(forKey: id) != nil else { return }
        await synchronizeTargets()
    }

    private func startMonitor() async {
        let candidate: ProcessMonitor
        do {
            candidate = try ProcessMonitor(
                pids: Set(subscriptions.values.map(\.pid)), metrics: [.cpu, .memory], interval: .seconds(2),
            )
        } catch {
            await failSubscriptions()
            return
        }
        monitor = candidate
        do {
            let events = try await candidate.events()
            guard monitor === candidate else { return }
            pump = Task.detached { [weak self] in
                for await event in events {
                    guard !Task.isCancelled else { break }
                    await self?.receive(event, from: candidate)
                }
            }
        } catch {
            if monitor === candidate {
                await failSubscriptions()
            }
        }
    }

    private func synchronizeTargets() async {
        revision += 1
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        // actorの再入中に対象が変わっても、setPIDsを並列実行せず最新の集合を反映します。
        while let current = monitor {
            let revision = revision
            let pids = Set(subscriptions.values.map(\.pid))
            if pids.isEmpty {
                monitor = nil
                pump?.cancel()
                pump = nil
                await current.finish()
            } else {
                do {
                    try await current.setPIDs(pids)
                } catch {
                    if monitor === current {
                        await failSubscriptions()
                    }
                }
            }
            if self.revision == revision {
                return
            }
        }
    }

    private func receive(_ event: ProcessMonitorEvent, from source: ProcessMonitor) async {
        guard monitor === source else { return }
        switch event {
        case let .samples(batch):
            let grouped = Dictionary(grouping: subscriptions.values, by: \.pid)
            for sample in batch.samples {
                for subscription in grouped[sample.pid] ?? [] {
                    subscription.continuation.yield(.sample(sample))
                }
            }
        case let .processEnded(pid, _, _):
            let ended = subscriptions.filter { $0.value.pid == pid }
            for (id, subscription) in ended {
                subscriptions.removeValue(forKey: id)
                subscription.continuation.yield(.ended)
                subscription.continuation.finish()
            }
            await synchronizeTargets()
        case .finished:
            await failSubscriptions()
        }
    }

    private func failSubscriptions() async {
        let current = monitor
        monitor = nil
        pump?.cancel()
        pump = nil
        let ended = subscriptions
        subscriptions.removeAll()
        for subscription in ended.values {
            subscription.continuation.yield(.failed)
            subscription.continuation.finish()
        }
        await current?.finish()
    }
}
