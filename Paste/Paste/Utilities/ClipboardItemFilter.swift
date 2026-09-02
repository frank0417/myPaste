import Foundation

enum ClipboardItemFilter {
    static func matches(_ item: ClipboardItem, appState: AppState) -> Bool {
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

        let q = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }

        let haystack = [
            item.previewTitle,
            item.previewSubtitle,
            item.plainText,
            item.sourceAppName,
            item.primaryAutoTag?.displayName
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        return haystack.contains(q)
    }

    static func filter(_ items: [ClipboardItem], appState: AppState) -> [ClipboardItem] {
        items.filter { matches($0, appState: appState) }
    }
}
