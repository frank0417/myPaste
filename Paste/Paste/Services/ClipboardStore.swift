import AppKit
import Foundation
import SwiftData
import Combine

@MainActor
final class ClipboardStore: ObservableObject {
    private let modelContext: ModelContext
    private let monitor = ClipboardMonitor.shared
    private weak var appState: AppState?

    init(modelContext: ModelContext, appState: AppState) {
        self.modelContext = modelContext
        self.appState = appState
        monitor.onNewItem = { [weak self] payload in
            self?.ingest(payload)
        }
    }

    func startMonitoringIfNeeded() {
        guard appState?.isMonitoringEnabled != false else {
            monitor.stop()
            return
        }
        monitor.start()
    }

    func stopMonitoring() {
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
        try? modelContext.save()
        enforceHistoryLimit()
    }

    func paste(_ item: ClipboardItem) {
        writeToPasteboard(item)
        item.pasteCount += 1
        item.updatedAt = .now
        try? modelContext.save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.simulatePasteKeystroke()
        }
    }

    func copyOnly(_ item: ClipboardItem) {
        writeToPasteboard(item)
        item.updatedAt = .now
        try? modelContext.save()
    }

    func togglePin(_ item: ClipboardItem) {
        item.isPinned.toggle()
        try? modelContext.save()
    }

    func toggleFavorite(_ item: ClipboardItem) {
        item.isFavorite.toggle()
        try? modelContext.save()
    }

    func delete(_ item: ClipboardItem) {
        modelContext.delete(item)
        try? modelContext.save()
    }

    func clearHistory(keepPinned: Bool = true) {
        let descriptor = FetchDescriptor<ClipboardItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }
        for item in items where !(keepPinned && item.isPinned) {
            modelContext.delete(item)
        }
        try? modelContext.save()
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
                "createdAt": ISO8601DateFormatter().string(from: item.createdAt),
                "updatedAt": ISO8601DateFormatter().string(from: item.updatedAt),
                "pasteCount": item.pasteCount
            ]
            if let text = item.plainText { row["plainText"] = text }
            if let sub = item.previewSubtitle { row["previewSubtitle"] = sub }
            if let hex = item.colorHex { row["colorHex"] = hex }
            if let app = item.sourceAppName { row["sourceAppName"] = app }
            if let board = item.board?.name { row["board"] = board }
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
            if let data = item.imageData, let image = NSImage(data: data) {
                pb.writeObjects([image])
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

    private func enforceHistoryLimit() {
        let limit = appState?.maxHistoryCount ?? 500
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { !$0.isPinned },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let items = try? modelContext.fetch(descriptor), items.count > limit else { return }
        for item in items.suffix(from: limit) {
            modelContext.delete(item)
        }
        try? modelContext.save()
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
