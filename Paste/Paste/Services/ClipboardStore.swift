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
        writeToPasteboard(item) { [weak self] in
            guard let self else { return }
            item.pasteCount += 1
            item.updatedAt = .now
            try? self.modelContext.save()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                // Accessibility is only required to synthesize ⌘V. Content is already on the pasteboard.
                if !AccessibilityPermission.isTrusted {
                    AccessibilityPermission.requestIfNeeded(prompt: true)
                }
                Self.simulatePasteKeystroke()
            }
        }
    }

    func copyOnly(_ item: ClipboardItem) {
        writeToPasteboard(item) { [weak self] in
            item.updatedAt = .now
            try? self?.modelContext.save()
        }
    }

    /// Whether "识别文字" makes sense for this item: an image whose text has not
    /// been read yet, and that is not already being read.
    func canRecognizeText(in item: ClipboardItem) -> Bool {
        item.contentType == .image
            && item.imageData != nil
            && (item.plainText ?? "").isEmpty
            && !recognizingItemIDs.contains(item.id)
    }

    /// Items with OCR in flight, so the menu does not offer it twice.
    @Published private(set) var recognizingItemIDs: Set<UUID> = []

    /// Reads the text in a screenshot on demand and attaches it to the item, so the
    /// user picks per capture whether they want the words. Runs Vision off the main
    /// actor; the picture stays, the text becomes searchable and copyable.
    func recognizeText(in item: ClipboardItem) {
        guard canRecognizeText(in: item), let data = item.imageData else { return }
        let id = item.id
        recognizingItemIDs.insert(id)
        // Strong, immutable capture: a weak `self` is a captured var, which the
        // compiler rejects inside concurrently-executing code.
        Self.recognitionQueue.async { [self] in
            let text = TextRecognizer.recognize(imageData: data)
            Task { @MainActor in
                self.recognizingItemIDs.remove(id)
                self.attachRecognizedText(text, to: id)
            }
        }
    }

    private static let recognitionQueue = DispatchQueue(
        label: "com.mypaste.PasteNest.recognize-text",
        qos: .userInitiated
    )

    private func attachRecognizedText(_ text: String?, to id: UUID) {
        var descriptor = FetchDescriptor<ClipboardItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        guard let text, !text.isEmpty else {
            ScreenshotHUD.shared.show(thumbnail: nil, title: ScreenshotL10n.string(.recognizeText), detail: ScreenshotL10n.string(.ocrEmpty))
            return
        }
        attach(text, to: item)
        ScreenshotHUD.shared.show(
            thumbnail: item.thumbnailData.flatMap(NSImage.init(data:)),
            title: item.previewTitle,
            detail: ScreenshotL10n.hudRecognizedMenu(TextRecognizer.characterCount(of: text))
        )
    }

    /// The screenshot action bar reads text before the store hands out an item, so
    /// it identifies the capture by content hash. The bar already reported the
    /// result; this only records it.
    func attachRecognizedText(_ text: String, toContentHash hash: String) {
        guard !text.isEmpty else { return }
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentHash == hash },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        attach(text, to: item)
    }

    private func attach(_ text: String, to item: ClipboardItem) {
        item.plainText = text
        let count = TextRecognizer.characterCount(of: text)
        let base = ScreenshotL10n.stripOCRSuffix(item.previewSubtitle)
        item.previewSubtitle = [base, ScreenshotL10n.ocrAttached(count)].compactMap { $0 }.joined(separator: " · ")
        // The keyword field cache and the panel memo key off updatedAt; without a bump
        // the new words would stay invisible to search until the next paste.
        item.updatedAt = .now
        try? modelContext.save()
        EmbeddingIndex.shared.upsert(id: item.id, text: item.searchableText)
    }

    /// Saves an image item as a PNG through a save panel.
    func saveImage(_ item: ClipboardItem) {
        guard item.contentType == .image, let data = item.imageData else { return }
        let png = Self.pngData(from: data) ?? data
        let name = "PasteNest \(item.previewTitle.replacingOccurrences(of: "/", with: "-")).png"
        ScreenshotService.saveImage(png, suggestedName: name, thumbnail: item.thumbnailData.flatMap(NSImage.init(data:)))
    }

    /// Copied images arrive as TIFF or PNG; the file on disk should always be PNG.
    private static func pngData(from data: Data) -> Data? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        return rep.representation(using: .png, properties: [:])
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
        ImageCache.shared.remove(id: id)
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
        removed.forEach { ImageCache.shared.remove(id: $0) }
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

    /// The completion runs on the main thread once the pasteboard holds the content.
    /// Image encodings are prepared off-main (and cached per item), so pasting a
    /// screenshot no longer stalls the UI.
    private func writeToPasteboard(_ item: ClipboardItem, completion: @escaping () -> Void = {}) {
        monitor.ignoreNextPasteboardChange()
        switch item.contentType {
        case .image:
            // Screenshots carry their recognized text in plainText; pasting one offers
            // both, exactly like the capture did.
            let itemID = item.id
            guard let data = item.imageData else {
                completion()
                return
            }
            let text = item.plainText
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                var pasteboardItem: NSPasteboardItem?
                if let encodings = ImageCache.shared.pasteEncodings(id: itemID, imageData: data) {
                    let pbItem = NSPasteboardItem()
                    pbItem.setData(encodings.tiff, forType: .tiff)
                    if let png = encodings.png {
                        pbItem.setData(png, forType: .png)
                    }
                    if let text, !text.isEmpty {
                        pbItem.setString(text, forType: .string)
                    }
                    pasteboardItem = pbItem
                }
                DispatchQueue.main.async {
                    self?.monitor.ignoreNextPasteboardChange()
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    if let pasteboardItem {
                        pb.writeObjects([pasteboardItem])
                    }
                    completion()
                }
            }
        case .file:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(item.fileURLs as [NSURL])
            completion()
        case .color:
            let pb = NSPasteboard.general
            pb.clearContents()
            if let hex = item.colorHex ?? item.plainText {
                pb.setString(hex, forType: .string)
            }
            completion()
        default:
            let pb = NSPasteboard.general
            pb.clearContents()
            if let rtf = item.richTextData {
                pb.setData(rtf, forType: .rtf)
            }
            if let text = item.plainText {
                pb.setString(text, forType: .string)
            }
            completion()
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
        removed.forEach { ImageCache.shared.remove(id: $0) }
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
        // Favorites are kept on purpose, so they must not count against the cap
        // or be trimmed by it.
        let counting = #Predicate<ClipboardItem> { !$0.isPinned && !$0.isFavorite }
        let count = (try? modelContext.fetchCount(FetchDescriptor<ClipboardItem>(predicate: counting))) ?? 0
        let excess = count - limit
        guard excess > 0 else { return }

        // Fetch only the records that will actually be deleted, oldest first —
        // materializing the whole history on every copy was measurable on main.
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: counting,
            sortBy: [SortDescriptor(\.updatedAt, order: .forward)]
        )
        descriptor.fetchLimit = excess
        guard let stale = try? modelContext.fetch(descriptor), !stale.isEmpty else { return }
        let removed = stale.map(\.id)
        for item in stale {
            modelContext.delete(item)
        }
        try? modelContext.save()
        EmbeddingIndex.shared.remove(ids: removed)
    }

    /// Rewrite oversized TIFF copies to PNG/JPEG a couple at a time so a library
    /// built before compression does not keep 200 MB of uncompressed screenshots
    /// in the SwiftData context. Oldest first — those are the most likely TIFFs.
    func scheduleImageCompaction() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.compactOversizedImages(after: nil, passes: 0)
        }
    }

    private func compactOversizedImages(after: Date?, passes: Int) {
        guard passes < 20 else { return }
        let cutoff = after ?? Date.distantPast
        var descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.contentTypeRaw == "image" && $0.createdAt > cutoff },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 2
        guard let batch = try? modelContext.fetch(descriptor), !batch.isEmpty else { return }
        var saved = false
        for item in batch {
            guard let data = item.imageData, ClipboardMonitor.shouldCompactStoredImage(data) else { continue }
            guard let compacted = ClipboardMonitor.compactedImageData(data), compacted.count < data.count else {
                continue
            }
            item.imageData = compacted
            item.contentHash = ClipboardMonitor.hashData(compacted)
            ImageCache.shared.remove(id: item.id)
            saved = true
        }
        if saved {
            try? modelContext.save()
        }
        guard let lastDate = batch.last?.createdAt else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.compactOversizedImages(after: lastDate, passes: passes + 1)
        }
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
