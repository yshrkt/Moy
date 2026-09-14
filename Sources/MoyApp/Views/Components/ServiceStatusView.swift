import MoyKit
import SwiftUI

struct ServiceStatusView: View {
    let status: ServiceStatus?
    var statusUnavailable = false
    var showsRuntime = true

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .foregroundStyle(.secondary)
            if showsRuntime, let runtimeTitle {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(runtimeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var title: String {
        if statusUnavailable {
            return L10n.Services.statusUnavailable
        }
        guard let status else { return L10n.Services.unknown }
        return switch status.registration {
        case .disabled: L10n.Services.disabled
        case .enabled: L10n.Services.enabled
        case .plistOnly, .loadedOnly: L10n.Services.needsAttention
        }
    }

    private var runtimeTitle: String? {
        guard let status else { return nil }
        return switch status.runtime {
        case .notLoaded: L10n.Services.notLoaded
        case .waiting: L10n.Services.waiting
        case let .running(pid): "\(L10n.Services.running) (\(pid))"
        }
    }

    private var color: Color {
        if statusUnavailable {
            return .red
        }
        guard let status else { return .secondary }
        switch status.registration {
        case .disabled: return .secondary
        case .plistOnly, .loadedOnly: return .orange
        case .enabled:
            if case .running = status.runtime {
                return .green
            }
            return .blue
        }
    }
}

extension ServiceStatus {
    var allowsEnable: Bool {
        registration == .disabled
    }

    var allowsDisable: Bool {
        registration != .disabled
    }

    var allowsRestart: Bool {
        registration == .enabled
    }
}
