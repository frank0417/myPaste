import Foundation
import SwiftData

/// Automatic tags derived from clipboard content type (图片 / 链接 / 富文本 …).
enum AutoTag: String, CaseIterable, Identifiable, Codable {
    case image
    case link
    case richText
    case text
    case code
    case file
    case color
    case snippet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .image: return "图片"
        case .link: return "链接"
        case .richText: return "富文本"
        case .text: return "文本"
        case .code: return "代码"
        case .file: return "文件"
        case .color: return "颜色"
        case .snippet: return "长文本"
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .link: return "link"
        case .richText: return "doc.richtext"
        case .text: return "text.alignleft"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .file: return "doc"
        case .color: return "paintpalette"
        case .snippet: return "text.quote"
        }
    }

    var accentHex: String {
        switch self {
        case .image: return "#7C3AED"
        case .link: return "#0D9488"
        case .richText: return "#EE6C4D"
        case .text: return "#3D5A80"
        case .code: return "#059669"
        case .file: return "#64748B"
        case .color: return "#F59E0B"
        case .snippet: return "#2563EB"
        }
    }

    static func from(contentType: ClipboardContentType) -> AutoTag {
        switch contentType {
        case .image: return .image
        case .link: return .link
        case .richText: return .richText
        case .text: return .text
        case .code: return .code
        case .file: return .file
        case .color: return .color
        case .snippet: return .snippet
        }
    }
}

enum AutoTagService {
    /// `autoTags` is read for every row/card render; decoding the JSON each time is
    /// wasted work, so the decoded list is memoized against the raw stored string.
    private static let listCacheLock = NSLock()
    private static var listCache: [UUID: (raw: String?, tags: [String])] = [:]

    static func cachedTags(for item: ClipboardItem) -> [String] {
        let raw = item.autoTagsJSON
        listCacheLock.lock()
        if let cached = listCache[item.id], cached.raw == raw {
            listCacheLock.unlock()
            return cached.tags
        }
        listCacheLock.unlock()

        let decoded: [String]
        if let raw,
           let data = raw.data(using: .utf8),
           let tags = try? JSONDecoder().decode([String].self, from: data),
           !tags.isEmpty {
            decoded = tags
        } else {
            decoded = tags(for: item.contentType, hasRichText: item.richTextData != nil)
        }

        listCacheLock.lock()
        if listCache.count > 4000 {
            listCache.removeAll(keepingCapacity: false)
        }
        listCache[item.id] = (raw, decoded)
        listCacheLock.unlock()
        return decoded
    }

    static func tags(for contentType: ClipboardContentType, hasRichText: Bool) -> [String] {
        var type = contentType
        if hasRichText, contentType == .text || contentType == .snippet {
            type = .richText
        }
        return [AutoTag.from(contentType: type).rawValue]
    }

    static func apply(to item: ClipboardItem) {
        let tags = tags(for: item.contentType, hasRichText: item.richTextData != nil)
        item.autoTags = tags
    }

    static func apply(contentType: ClipboardContentType, hasRichText: Bool, to item: ClipboardItem) {
        item.contentType = contentType
        item.autoTags = tags(for: contentType, hasRichText: hasRichText)
    }

    static func backfillIfNeeded(in context: ModelContext) {
        // Only items that never received a tag — fetching the whole table at launch
        // would load every image blob into the main context for nothing.
        let descriptor = FetchDescriptor<ClipboardItem>(
            predicate: #Predicate { $0.autoTagsJSON == nil }
        )
        guard let items = try? context.fetch(descriptor), !items.isEmpty else { return }
        for item in items {
            apply(to: item)
        }
        try? context.save()
    }
}

extension ClipboardItem {
    var autoTags: [String] {
        get { AutoTagService.cachedTags(for: self) }
        set {
            autoTagsJSON = (try? String(data: JSONEncoder().encode(newValue), encoding: .utf8)) ?? "[]"
        }
    }

    var primaryAutoTag: AutoTag? {
        guard let raw = autoTags.first else { return nil }
        return AutoTag(rawValue: raw)
    }
}
