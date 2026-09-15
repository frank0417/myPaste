import AppKit
import Foundation
import SwiftData
import Combine

@MainActor
final class ClipboardStore: ObservableObject {
    private let modelContext: ModelContext
    private let monitor = ClipboardMonitor.shared
    private weak var appState: AppState?
    /// Only one store should own the monitor callback. UI panels must pass false or they
    /// overwrite the launch-time handler and then deallocate when the menu closes — breaking capture.
    private let ownsMonitor: Bool
    /// Sweeping on every copy would refetch the whole history; once in a while is enough
    /// for a policy measured in days.
    private static let retentionSweepInterval: TimeInterval = 15 * 60
    private var lastRetentionSweep: Date?

    init(modelContext: ModelContext, appState: AppState, ownsMonitor: Bool = false) {
        self.modelContext = modelContext
        self.appState = appState
        self.ownsMonitor = ownsMonitor
        if ownsMonitor {
            monitor.onNewItem = { [weak self] payload in
                self?.ingest(payload)
            }
        }
    }

    func startMonitoringIfNeeded() {
        guard ownsMonitor else { return }
        guard appState?.isMonitoringEnabled != false else {
            monitor.stop()
            return
        }
        monitor.start()
    }

    func stopMonitoring() {
        guard ownsMonitor else { return }
        monitor.stop()
    }

    func ingest(_ payload: CapturedClipboardPayload) {
        let hash = payload.contentHash
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentHash == hash },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.updatedAt = .now
            try? modelContext.save()
            EmbeddingIndex.shared.upsert(id: existing.id, text: existing.searchableText)
            return
        }

        let item = ClipboardItem(
            contentType: payload.contentType,
            plainText: payload.plainText,
            richTextData: payload.richTextData,
            imageData: payload.imageData,
            thumbnailData: payload.thumbnailData,
            fileURLs: payload.fileURLs,
            sourceAppBundleID: payload.sourceAppBundleID,
            sourceAppName: payload.sourceAppName,
            contentHash: payload.contentHash,
            previewTitle: payload.previewTitle,
            previewSubtitle: payload.previewSubtitle,
            colorHex: payload.colorHex
        )
        modelContext.insert(item)
        AutoTagService.apply(to: item)
        try? modelContext.save()
        EmbeddingIndex.shared.upsert(id: item.id, text: item.searchableText)
        enforceRetentionIfNeeded()
        enforceHistoryLimit()
    }

    func paste(_ item: ClipboardItem) {
        writeToPasteboard(item)
        item.pasteCount += 1
        item.updatedAt = .now
        try? modelContext.save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            // Accessibility is only required to synthesize ⌘V. Content is already on the pasteboard.
            if !AccessibilityPermission.isTrusted {
                AccessibilityPermission.requestIfNeeded(prompt: true)
            }
            Self.simulatePasteKeystroke()
        }
    }

    func copyOnly(_ item: ClipboardItem) {
        writeToPasteboard(item)
        item.updatedAt = .now
        try? modelContext.save()
    }

    /// Copies only the text an item carries — for a screenshot, the recognized text
    /// without the picture tagging along.
    func copyText(_ item: ClipboardItem) {
        guard let text = item.plainText, !text.isEmpty else { return }
        monitor.ignoreNextPasteboardChange()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        item.updatedAt = .now
        try? modelContext.save()
    }

    func togglePin(_ item: ClipboardItem) {
        item.isPinned.toggle()
        try? modelContext.save()
    }

    func toggleFavorite(_ item: ClipboardItem) {
        setFavorite(!item.isFavorite, for: item)
    }

    func setFavorite(_ favorite: Bool, for item: ClipboardItem) {
        guard item.isFavorite != favorite else { return }
        item.isFavorite = favorite
        if favorite {
            item.favoritedAt = .now
        } else {
            item.favoritedAt = nil
            // Taking something out of the folder restarts its retention window — it must
            // not disappear on the next sweep just because it was copied days ago.
            item.updatedAt = .now
        }
        try? modelContext.save()
    }

    /// Tagging files the item into the folder as well: a category on something the user
    /// never kept would vanish with the item.
    func addFavoriteTag(_ raw: String, to item: ClipboardItem) {
        guard let tag = FavoriteTagCatalog.normalize(raw) else { return }
        setFavorite(true, for: item)
        item.favoriteTags = FavoriteTagCatalog.adding(tag, to: item.favoriteTags)
        try? modelContext.save()
    }

    func removeFavoriteTag(_ tag: String, from item: ClipboardItem) {
        item.favoriteTags = FavoriteTagCatalog.removing(tag, from: item.favoriteTags)
        try? modelContext.save()
    }

    func toggleFavoriteTag(_ tag: String, for item: ClipboardItem) {
        if FavoriteTagCatalog.contains(tag, in: item.favoriteTags) {
            removeFavoriteTag(tag, from: item)
        } else {
            addFavoriteTag(tag, to: item)
        }
    }

    /// Drops a category everywhere; the favorites themselves stay in the folder.
    func deleteFavoriteTag(_ tag: String) {
        let descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.isFavorite })
        guard let favorites = try? modelContext.fetch(descriptor) else { return }
        for item in favorites where FavoriteTagCatalog.contains(tag, in: item.favoriteTags) {
            item.favoriteTags = FavoriteTagCatalog.removing(tag, from: item.favoriteTags)
        }
        try? modelContext.save()
    }

    func delete(_ item: ClipboardItem) {
        let id = item.id
        modelContext.delete(item)
        try? modelContext.save()
        EmbeddingIndex.shared.remove(ids: [id])
    }

    func clearHistory(keepPinned: Bool = true) {
        let descriptor = FetchDescriptor<ClipboardItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }
        var removed: [UUID] = []
        for item in items where !(keepPinned && item.isPinned) {
            removed.append(item.id)
            modelContext.delete(item)
        }
        try? modelContext.save()
        EmbeddingIndex.shared.remove(ids: removed)
    }

    func assign(item: ClipboardItem, to board: ClipboardBoard?) {
        item.board = board
        try? modelContext.save()
    }

    func exportJSON() -> Data? {
        let descriptor = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        guard let items = try? modelContext.fetch(descriptor) else { return nil }
        let rows: [[String: Any]] = items.map { item in
            var row: [String: Any] = [
                "id": item.id.uuidString,
                "contentType": item.contentTypeRaw,
                "previewTitle": item.previewTitle,
                "isPinned": item.isPinned,
                "isFavorite": item.isFavorite,
                "createdAt": ISO8601DateFormatter().string(from: item.createdAt),
                "updatedAt": ISO8601DateFormatter().string(from: item.updatedAt),
                "pasteCount": item.pasteCount
            ]
            if let text = item.plainText { row["plainText"] = text }
            if let sub = item.previewSubtitle { row["previewSubtitle"] = sub }
            if let hex = item.colorHex { row["colorHex"] = hex }
            if let app = item.sourceAppName { row["sourceAppName"] = app }
            if let board = item.board?.name { row["board"] = board }
            if let favoritedAt = item.favoritedAt {
                row["favoritedAt"] = ISO8601DateFormatter().string(from: favoritedAt)
            }
            if !item.favoriteTags.isEmpty { row["favoriteTags"] = item.favoriteTags }
            if !item.autoTags.isEmpty { row["autoTags"] = item.autoTags }
            if let thumb = item.thumbnailData ?? item.imageData {
                row["thumbnailBase64"] = thumb.base64EncodedString()
            }
            return row
        }
        return try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
    }

    private func writeToPasteboard(_ item: ClipboardItem) {
        monitor.ignoreNextPasteboardChange()
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.contentType {
        case .image:
            // Screenshots carry their recognized text in plainText; pasting one offers
            // both, exactly like the capture did.
            if let data = item.imageData,
               let pasteboardItem = ClipboardMonitor.imagePasteboardItem(imageData: data, text: item.plainText) {
                pb.writeObjects([pasteboardItem])
            }
        case .file:
            pb.writeObjects(item.fileURLs as [NSURL])
        case .color:
            if let hex = item.colorHex ?? item.plainText {
                pb.setString(hex, forType: .string)
            }
        default:
            if let rtf = item.richTextData {
                pb.setData(rtf, forType: .rtf)
            }
            if let text = item.plainText {
                pb.setString(text, forType: .string)
            }
        }
    }

    /// Favorites (and pinned items) are the long-term library; everything else only
    /// lives for the configured number of days.
    @discardableResult
    func enforceRetention() -> Int {
        lastRetentionSweep = .now
        let days = RetentionPolicy.clampDays(appState?.keepUnfavoritedDays ?? RetentionPolicy.defaultDays)
        let cutoff = RetentionPolicy.cutoff(days: days, now: .now)
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isFavorite && !$0.isPinned && $0.updatedAt < cutoff }
        )
        guard let stale = try? modelContext.fetch(descriptor), !stale.isEmpty else { return 0 }
        let removed = stale.map(\.id)
        for item in stale {
            modelContext.delete(item)
        }
        try? modelContext.save()
        EmbeddingIndex.shared.remove(ids: removed)
        return removed.count
    }

    private func enforceRetentionIfNeeded() {
        if let lastRetentionSweep,
           Date.now.timeIntervalSince(lastRetentionSweep) < Self.retentionSweepInterval {
            return
        }
        enforceRetention()
    }

    private func enforceHistoryLimit() {
        let limit = appState?.maxHistoryCount ?? 500
        let descriptor = FetchDescriptor<ClipboardItem>(
            // Favorites are kept on purpose, so they must not count against the cap
            // or be trimmed by it.
            predicate: #Predicate { !$0.isPinned && !$0.isFavorite },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let items = try? modelContext.fetch(descriptor), items.count > limit else { return }
        var removed: [UUID] = []
        for item in items.suffix(from: limit) {
            removed.append(item.id)
            modelContext.delete(item)
        }
        try? modelContext.save()
        EmbeddingIndex.shared.remove(ids: removed)
    }

    private static func simulatePasteKeystroke() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
