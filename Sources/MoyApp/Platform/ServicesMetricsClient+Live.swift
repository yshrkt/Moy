import Foundation
import MoyMetrics

extension ServicesMetricsClient {
    static let live = Self(
        events: { pid in
            AsyncStream { continuation in
                let task = Task {
                    continuation.yield(.capacity(ProcessInfo.processInfo.physicalMemory))
                    do {
                        let monitor = try ProcessMonitor(pids: [pid], metrics: [.cpu, .memory], interval: .seconds(2))
                        let events = try await monitor.events()
                        await withTaskCancellationHandler {
                            for await event in events {
                                guard !Task.isCancelled else { break }
                                switch event {
                                case let .samples(batch):
                                    if let sample = batch.samples.first(where: { $0.pid == pid }) {
                                        continuation.yield(.sample(sample))
                                    }
                                case .processEnded, .finished:
                                    continuation.yield(.ended)
                                    await monitor.finish()
                                    continuation.finish()
                                    return
                                }
                            }
                        } onCancel: {
                            Task { await monitor.finish() }
                        }
                        await monitor.finish()
                    } catch {
                        if !Task.isCancelled {
                            continuation.yield(.failed)
                        }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
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
