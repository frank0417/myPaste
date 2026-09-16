import Foundation
import Combine

/// Lightweight sync status facade. Persistence sync is handled by SwiftData + CloudKit.
@MainActor
final class SyncService: ObservableObject {
    enum Status: Equatable {
        case idle
        case syncing
        case synced(Date)
        case offline
        case error(String)

        var label: String {
            switch self {
            case .idle: return PanelL10n.syncIdle
            case .syncing: return PanelL10n.syncing
            case .synced(let date):
                let formatter = RelativeDateTimeFormatter()
                formatter.locale = PanelL10n.locale
                return PanelL10n.syncedAgo(formatter.localizedString(for: date, relativeTo: .now))
            case .offline: return PanelL10n.offline
            case .error(let message): return PanelL10n.syncFailed(message)
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published var iCloudAvailable: Bool = true

    private var timer: Timer?

    func startStatusHeartbeat() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            let service = self
            Task { @MainActor in
                service?.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        // CloudKit availability is reflected by the container configuration.
        // We surface a friendly status for Settings / status bar.
        if !iCloudAvailable {
            status = .offline
            return
        }
        switch status {
        case .syncing:
            break
        default:
            status = .synced(.now)
        }
    }

    func markSyncing() {
        status = .syncing
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.status = .synced(.now)
        }
    }
}
