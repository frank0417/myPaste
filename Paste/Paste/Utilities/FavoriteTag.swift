import Foundation

/// Which slice of the favorites folder is on screen.
enum FavoriteScope: Equatable {
    case all
    case tag(String)
    case untagged

    var title: String {
        switch self {
        case .all: return "全部收藏"
        case .untagged: return FavoriteTagCatalog.untaggedTitle
        case .tag(let name): return name
        }
    }

    var tagName: String? {
        if case .tag(let name) = self { return name }
        return nil
    }
}

struct FavoriteTagCount: Identifiable, Equatable {
    let name: String
    let count: Int

    var id: String { name }
    var accentHex: String { FavoriteTagCatalog.accentHex(for: name) }
}

/// Free-form categories the user puts on favorites. Kept as plain strings on the item
/// so the folder grows with whatever the user types, instead of a fixed board list.
enum FavoriteTagCatalog {
    static let untaggedTitle = "未分类"
    static let suggestions = ["工作", "灵感", "代码", "资料", "待办"]
    static let maxTagsPerItem = 5
    static let maxNameLength = 12

    static let palette = [
        "#0D9488", "#EE6C4D", "#7C3AED", "#2563EB",
        "#F59E0B", "#059669", "#DB2777", "#3D5A80"
    ]

    /// `nil` for anything that would become an unusable category name.
    static func normalize(_ raw: String) -> String? {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(maxNameLength))
    }

    static func sanitize(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for tag in tags {
            guard let name = normalize(tag) else { continue }
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(name)
            if result.count == maxTagsPerItem { break }
        }
        return result
    }

    static func adding(_ tag: String, to tags: [String]) -> [String] {
        guard let name = normalize(tag) else { return sanitize(tags) }
        return sanitize(tags + [name])
    }

    static func removing(_ tag: String, from tags: [String]) -> [String] {
        guard let name = normalize(tag) else { return sanitize(tags) }
        return sanitize(tags.filter { normalize($0)?.lowercased() != name.lowercased() })
    }

    static func contains(_ tag: String, in tags: [String]) -> Bool {
        guard let name = normalize(tag)?.lowercased() else { return false }
        return tags.contains { normalize($0)?.lowercased() == name }
    }

    /// Stable so a category keeps its color between launches and across windows.
    static func accentHex(for tag: String) -> String {
        let name = normalize(tag) ?? tag
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[abs(sum) % palette.count]
    }

    /// Most-used categories first, so the chip row leads with the ones in play.
    static func counts(in tagLists: [[String]]) -> [FavoriteTagCount] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for list in tagLists {
            for tag in sanitize(list) {
                let key = tag.lowercased()
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = tag }
            }
        }
        return counts
            .map { FavoriteTagCount(name: display[$0.key] ?? $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.name < rhs.name
            }
    }

    /// Deduped names for a category picker: what the folder already uses, then the
    /// untouched defaults. Unlike `sanitize` this is a menu, so it is not capped by
    /// how many tags a single item may carry.
    static func sanitizedMenuOptions(known: [String], suggestions: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for tag in known + suggestions {
            guard let name = normalize(tag) else { continue }
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(name)
        }
        return result
    }

    /// Defaults worth offering in the tag menu — only the ones nobody has used yet.
    static func unusedSuggestions(existing: [String]) -> [String] {
        let used = Set(existing.compactMap { normalize($0)?.lowercased() })
        return suggestions.filter { !used.contains($0.lowercased()) }
    }
}

extension ClipboardItem {
    var favoriteTags: [String] {
        get {
            guard let favoriteTagsJSON,
                  let data = favoriteTagsJSON.data(using: .utf8),
                  let tags = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return FavoriteTagCatalog.sanitize(tags)
        }
        set {
            let clean = FavoriteTagCatalog.sanitize(newValue)
            favoriteTagsJSON = (try? String(data: JSONEncoder().encode(clean), encoding: .utf8)) ?? "[]"
        }
    }
}

extension Array where Element == ClipboardItem {
    var favoriteTagCounts: [FavoriteTagCount] {
        FavoriteTagCatalog.counts(in: filter(\.isFavorite).map(\.favoriteTags))
    }

    /// Names used anywhere in the folder — the pool a tag menu offers.
    var favoriteTagNames: [String] {
        favoriteTagCounts.map(\.name)
    }
}
