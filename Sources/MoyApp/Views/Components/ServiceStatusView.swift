import MoyKit
import SwiftUI

struct ServiceStatusView: View {
    let status: ServiceStatus?
    var hasStatusError = false

    var body: some View {
        let presentation = ServiceStatusPresentation(status: status, hasError: hasStatusError)
        if presentation == .loading {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(L10n.Services.loading)
        } else {
            HStack(spacing: 6) {
                Circle()
                    .fill(presentation.color)
                    .frame(width: 8, height: 8)
                Text(presentation.title)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .help(presentation.help)
        }
    }
}

enum ServiceStatusPresentation: Equatable {
    case loading
    case running
    case waiting
    case disabled
    case needsAttention
    case error

    init(status: ServiceStatus?, hasError: Bool) {
        if hasError {
            self = .error
            return
        }
        guard let status else {
            self = .loading
            return
        }
        switch status.registration {
        case .disabled:
            self = .disabled
        case .plistOnly, .loadedOnly:
            self = .needsAttention
        case .enabled:
            self = switch status.runtime {
            case .running: .running
            case .waiting: .waiting
            case .notLoaded: .needsAttention
            }
        }
    }

    var title: String {
        switch self {
        case .loading: L10n.Services.loading
        case .running: L10n.Services.running
        case .waiting: L10n.Services.waiting
        case .disabled: L10n.Services.disabled
        case .needsAttention: L10n.Services.needsAttention
        case .error: L10n.Common.error
        }
    }

    var color: Color {
        switch self {
        case .loading, .disabled: .secondary
        case .running: .green
        case .waiting: .yellow
        case .needsAttention, .error: .red
        }
    }

    var help: String {
        switch self {
        case .error: L10n.Services.statusErrorHelp
        default: title
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
