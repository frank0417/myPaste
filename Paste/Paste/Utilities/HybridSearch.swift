import Foundation

enum HybridSearch {
    static let semanticFloor = 0.35

    struct Hit {
        var id: UUID
        var keyword: Double
        var semantic: Double
        var phrase: Bool
    }

    @MainActor
    static func rank(_ items: [ClipboardItem], appState: AppState) -> [ClipboardItem] {
        _ = appState.embeddingRevision
        let hard = items.filter { ClipboardItemFilter.matchesHard($0, appState: appState) }
        let query = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return hard }

        let keywordScores = Dictionary(uniqueKeysWithValues: hard.map { ($0.id, KeywordScorer.score(query: query, item: $0)) })
        let semanticScores = EmbeddingIndex.shared.scores(query: query, ids: hard.map(\.id))
        let folded = query.lowercased()

        var hits: [Hit] = []
        hits.reserveCapacity(hard.count)
        for item in hard {
            let keyword = keywordScores[item.id] ?? 0
            let semanticRaw = semanticScores[item.id] ?? 0
            let semantic = semanticRaw >= semanticFloor ? semanticRaw : 0
            if keyword <= 0 && semantic <= 0 { continue }
            let phrase = KeywordScorer.haystack(item: item).contains(folded)
            hits.append(Hit(id: item.id, keyword: keyword, semantic: semantic, phrase: phrase))
        }

        let fused = fuse(hits)
        let byID = Dictionary(uniqueKeysWithValues: hard.map { ($0.id, $0) })
        return fused.compactMap { byID[$0] }
    }

    /// Per-query min-max keyword + cosine, with an exact-phrase bonus so identifiers stay on top.
    static func fuse(_ hits: [Hit]) -> [UUID] {
        let maxKeyword = hits.map(\.keyword).max() ?? 0
        let scored: [(UUID, Double)] = hits.map { hit in
            let keyword = maxKeyword > 0 ? hit.keyword / maxKeyword : 0
            var score = keyword + hit.semantic
            if hit.phrase {
                score += 2.0
            }
            return (hit.id, score)
        }

        return scored.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.uuidString < rhs.0.uuidString
        }.map(\.0)
    }
}
