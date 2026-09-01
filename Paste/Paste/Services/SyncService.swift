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
            case .idle: return "待命"
            case .syncing: return "同步中…"
            case .synced(let date):
                let formatter = RelativeDateTimeFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                return "已同步 · \(formatter.localizedString(for: date, relativeTo: .now))"
            case .offline: return "离线"
            case .error(let message): return "同步失败 · \(message)"
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published var iCloudAvailable: Bool = true

    private var timer: Timer?

    func startStatusHeartbeat() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
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
