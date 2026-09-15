import Foundation
import NaturalLanguage

/// On-device sentence vectors via `NLContextualEmbedding`.
/// Stored beside the app (not CloudKit): vectors are derived and model-version-specific.
final class EmbeddingIndex: @unchecked Sendable {
    static let shared = EmbeddingIndex()
    static let maxCharacters = 2000

    var onDidUpdate: (() -> Void)?

    private struct Record: Codable {
        var modelID: String
        var vector: [Float]
    }

    private struct FilePayload: Codable {
        var format: Int
        var records: [String: Record]
    }

    private enum ScriptSpace: Hashable {
        case latin
        case cjk
    }

    private let embedQueue = DispatchQueue(label: "com.mypaste.PasteNest.embeddings", qos: .utility)
    private let recordLock = NSLock()
    private var records: [UUID: Record] = [:]
    private var models: [ScriptSpace: NLContextualEmbedding] = [:]
    private var loaded: Set<ScriptSpace> = []
    private var requesting: Set<ScriptSpace> = []
    private var pending: [(UUID, String)] = []
    private var persistWorkItem: DispatchWorkItem?
    private var didLoadFromDisk = false
    private var queryCache: (query: String, vector: [Float], modelID: String)?
    private var latestQuery: String = ""
    private var inflightQuery: String?

    private init() {}

    func prepare() {
        embedQueue.async { [weak self] in
            guard let self else { return }
            self.loadFromDiskIfNeeded()
            _ = self.warmup(.latin)
            _ = self.warmup(.cjk)
        }
    }

    func backfill(_ items: [(UUID, String)]) {
        embedQueue.async { [weak self] in
            guard let self else { return }
            self.loadFromDiskIfNeeded()
            self.pending.append(contentsOf: items)
            self.drainPending()
        }
    }

    func upsert(id: UUID, text: String) {
        embedQueue.async { [weak self] in
            guard let self else { return }
            self.loadFromDiskIfNeeded()
            switch self.upsertNow(id: id, text: text) {
            case .written:
                self.schedulePersist()
                self.notify()
            case .alreadyFresh:
                break
            case .deferred:
                self.pending.append((id, text))
                _ = self.warmup(Self.scriptSpace(for: text))
            }
        }
    }

    func remove(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        embedQueue.async { [weak self] in
            guard let self else { return }
            self.recordLock.lock()
            for id in ids { self.records.removeValue(forKey: id) }
            self.recordLock.unlock()
            self.pending.removeAll { ids.contains($0.0) }
            self.schedulePersist()
        }
    }

    /// Keyword path stays on the caller; query embedding never blocks the main thread.
    /// A cache miss returns `[:]` and refreshes via `onDidUpdate` when the vector is ready.
    func scores(query: String, ids: [UUID]) -> [UUID: Double] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !ids.isEmpty else { return [:] }

        recordLock.lock()
        let snapshot = records
        let cached = queryCache
        recordLock.unlock()

        guard let cached, cached.query == trimmed else {
            requestQueryEmbed(trimmed)
            return [:]
        }

        var out: [UUID: Double] = [:]
        out.reserveCapacity(ids.count)
        for id in ids {
            guard let record = snapshot[id], record.modelID == cached.modelID else { continue }
            let cosine = Self.dot(cached.vector, record.vector)
            if cosine > 0 {
                out[id] = Double(cosine)
            }
        }
        return out
    }

    private func requestQueryEmbed(_ query: String) {
        recordLock.lock()
        latestQuery = query
        if inflightQuery == query || queryCache?.query == query {
            recordLock.unlock()
            return
        }
        inflightQuery = query
        recordLock.unlock()

        embedQueue.async { [weak self] in
            guard let self else { return }
            self.loadFromDiskIfNeeded()
            let embedded = self.embedNow(query)
            var shouldNotify = false
            self.recordLock.lock()
            if self.inflightQuery == query {
                self.inflightQuery = nil
            }
            if self.latestQuery == query, let embedded {
                self.queryCache = (query, embedded.vector, embedded.modelID)
                shouldNotify = true
            }
            self.recordLock.unlock()
            if shouldNotify {
                self.notify()
            }
        }
    }

    private enum UpsertOutcome {
        case written
        case alreadyFresh
        case deferred
    }

    private func drainPending() {
        guard !pending.isEmpty else { return }
        var changed = 0
        var still: [(UUID, String)] = []
        let chunk = min(8, pending.count)
        let batch = Array(pending.prefix(chunk))
        pending.removeFirst(chunk)
        for item in batch {
            switch upsertNow(id: item.0, text: item.1) {
            case .written:
                changed += 1
            case .alreadyFresh:
                break
            case .deferred:
                still.append(item)
            }
        }
        pending.append(contentsOf: still)
        if changed > 0 {
            persistNow()
            notify()
        }
        guard !pending.isEmpty else { return }
        let pendingSpaces = Set(pending.map { Self.scriptSpace(for: $0.1) })
        if pendingSpaces.contains(where: { loaded.contains($0) }) {
            embedQueue.async { [weak self] in
                self?.drainPending()
            }
        } else {
            pendingSpaces.forEach { _ = warmup($0) }
        }
    }

    @discardableResult
    private func upsertNow(id: UUID, text: String) -> UpsertOutcome {
        let space = Self.scriptSpace(for: text)
        if SensitiveClipboardText.shouldSkipEmbedding(text) {
            return .alreadyFresh
        }
        if let existing = peek(id),
           let model = models[space],
           loaded.contains(space),
           existing.modelID == model.modelIdentifier {
            return .alreadyFresh
        }
        guard let embedded = embedNow(text) else {
            if loaded.contains(space) { return .alreadyFresh }
            return .deferred
        }
        recordLock.lock()
        records[id] = Record(modelID: embedded.modelID, vector: embedded.vector)
        recordLock.unlock()
        return .written
    }

    private func peek(_ id: UUID) -> Record? {
        recordLock.lock()
        defer { recordLock.unlock() }
        return records[id]
    }

    private func embedNow(_ text: String) -> (vector: [Float], modelID: String)? {
        let clipped = String(text.prefix(Self.maxCharacters))
        guard !SensitiveClipboardText.shouldSkipEmbedding(clipped) else { return nil }
        let space = Self.scriptSpace(for: clipped)
        guard let embedding = warmup(space) else { return nil }
        let language = Self.resolvedLanguage(for: clipped, model: embedding)
        guard let result = try? embedding.embeddingResult(for: clipped, language: language) else { return nil }
        guard let vector = Self.meanPool(result) else { return nil }
        return (vector, embedding.modelIdentifier)
    }

    @discardableResult
    private func warmup(_ space: ScriptSpace) -> NLContextualEmbedding? {
        if let embedding = models[space], loaded.contains(space) {
            return embedding
        }
        guard let embedding = models[space] ?? makeEmbedding(space) else { return nil }
        models[space] = embedding
        if !embedding.hasAvailableAssets {
            requestAssets(embedding, space: space)
            return nil
        }
        if !loaded.contains(space) {
            do {
                try embedding.load()
                loaded.insert(space)
            } catch {
                return nil
            }
        }
        return embedding
    }

    private func makeEmbedding(_ space: ScriptSpace) -> NLContextualEmbedding? {
        switch space {
        case .latin:
            return NLContextualEmbedding(language: .english)
                ?? NLContextualEmbedding(script: .latin)
        case .cjk:
            return NLContextualEmbedding(language: .simplifiedChinese)
                ?? NLContextualEmbedding(language: .traditionalChinese)
                ?? NLContextualEmbedding(language: .japanese)
                ?? NLContextualEmbedding(language: .korean)
        }
    }

    private func requestAssets(_ embedding: NLContextualEmbedding, space: ScriptSpace) {
        guard !requesting.contains(space) else { return }
        requesting.insert(space)
        embedding.requestAssets { [weak self] _, _ in
            guard let self else { return }
            self.embedQueue.async {
                self.requesting.remove(space)
                _ = self.warmup(space)
                self.drainPending()
                self.notify()
            }
        }
    }

    /// Every notification makes each observer re-render and re-rank. Backfill writes
    /// in batches of eight, so without coalescing a 500-item library re-renders the
    /// whole UI 60+ times at launch. Immediate first, then at most one trailing
    /// notification per interval. Called on `embedQueue` only.
    private var lastNotify: Date = .distantPast
    private var trailingNotifyScheduled = false
    private static let notifyInterval: TimeInterval = 0.4

    private func notify() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastNotify)
        if elapsed >= Self.notifyInterval {
            lastNotify = now
            DispatchQueue.main.async { [weak self] in
                self?.onDidUpdate?()
            }
            return
        }
        guard !trailingNotifyScheduled else { return }
        trailingNotifyScheduled = true
        embedQueue.asyncAfter(deadline: .now() + (Self.notifyInterval - elapsed)) { [weak self] in
            guard let self else { return }
            self.trailingNotifyScheduled = false
            self.lastNotify = Date()
            DispatchQueue.main.async { [weak self] in
                self?.onDidUpdate?()
            }
        }
    }

    private func schedulePersist() {
        persistWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistNow()
        }
        persistWorkItem = work
        embedQueue.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func persistNow() {
        recordLock.lock()
        let snapshot = records
        recordLock.unlock()
        let payload = FilePayload(
            format: 1,
            records: Dictionary(uniqueKeysWithValues: snapshot.map { ($0.key.uuidString, $0.value) })
        )
        guard let data = try? PropertyListEncoder().encode(payload) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    private func loadFromDiskIfNeeded() {
        guard !didLoadFromDisk else { return }
        didLoadFromDisk = true
        guard let data = try? Data(contentsOf: Self.fileURL),
              let payload = try? PropertyListDecoder().decode(FilePayload.self, from: data) else { return }
        var loadedRecords: [UUID: Record] = [:]
        for (key, value) in payload.records {
            if let id = UUID(uuidString: key) {
                loadedRecords[id] = value
            }
        }
        recordLock.lock()
        records = loadedRecords
        recordLock.unlock()
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PasteNest", isDirectory: true)
            .appendingPathComponent("embeddings.plist")
    }

    private static func scriptSpace(for text: String) -> ScriptSpace {
        let sample = String(text.prefix(800))
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if let language = recognizer.dominantLanguage {
            switch language {
            case .simplifiedChinese, .traditionalChinese, .japanese, .korean:
                return .cjk
            default:
                break
            }
        }
        let cjkCount = sample.filter(\.isCJK).count
        return cjkCount >= 2 ? .cjk : .latin
    }

    private static func resolvedLanguage(for text: String, model: NLContextualEmbedding) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(800)))
        if let language = recognizer.dominantLanguage, model.languages.contains(language) {
            return language
        }
        return model.languages.first
    }

    private static func meanPool(_ result: NLContextualEmbeddingResult) -> [Float]? {
        var sum: [Double]?
        var count = 0
        result.enumerateTokenVectors(in: result.string.startIndex..<result.string.endIndex) { vector, _ in
            if sum == nil {
                sum = vector
            } else if var acc = sum, acc.count == vector.count {
                for index in acc.indices {
                    acc[index] += vector[index]
                }
                sum = acc
            }
            count += 1
            return true
        }
        guard var sum, count > 0 else { return nil }
        let divisor = Double(count)
        for index in sum.indices {
            sum[index] /= divisor
        }
        var floats = sum.map { Float($0) }
        l2normalize(&floats)
        return floats
    }

    private static func l2normalize(_ vector: inout [Float]) {
        var ss: Float = 0
        for value in vector { ss += value * value }
        let norm = sqrt(ss)
        guard norm > 0 else { return }
        for index in vector.indices {
            vector[index] /= norm
        }
    }

    private static func dot(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 0 }
        var sum: Float = 0
        for index in lhs.indices {
            sum += lhs[index] * rhs[index]
        }
        return sum
    }
}
