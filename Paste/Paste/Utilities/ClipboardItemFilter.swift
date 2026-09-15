import Foundation

@MainActor
enum ClipboardItemFilter {
    static func matchesHard(_ item: ClipboardItem, appState: AppState) -> Bool {
        if appState.selectedFilter == .pinned || appState.showOnlyPinned {
            guard item.isPinned else { return false }
        } else if appState.selectedFilter != .all {
            switch appState.selectedFilter {
            case .text:
                guard [.text, .richText, .snippet].contains(item.contentType) else { return false }
            case .link:
                guard item.contentType == .link else { return false }
            case .image:
                guard item.contentType == .image else { return false }
            case .file:
                guard item.contentType == .file else { return false }
            case .code:
                guard item.contentType == .code else { return false }
            case .richText:
                guard item.contentType == .richText || item.richTextData != nil else { return false }
            case .color:
                guard item.contentType == .color else { return false }
            case .snippet:
                guard item.contentType == .snippet else { return false }
            case .all, .pinned:
                break
            }
        }

        if let tag = appState.selectedAutoTag {
            guard item.autoTags.contains(tag) else { return false }
        }
        return true
    }

    static func matches(_ item: ClipboardItem, appState: AppState) -> Bool {
        guard matchesHard(item, appState: appState) else { return false }
        let query = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return KeywordScorer.score(query: query, item: item) > 0
    }

    static func filter(_ items: [ClipboardItem], appState: AppState) -> [ClipboardItem] {
        HybridSearch.rank(items, appState: appState)
    }
}
