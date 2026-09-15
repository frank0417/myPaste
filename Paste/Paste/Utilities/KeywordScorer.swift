import Foundation

struct KeywordDocument {
    var title: String
    var subtitle: String?
    var body: String?
    var source: String?
    var tag: String?
}

enum KeywordScorer {
    private static let stopwords: Set<String> = [
        "the", "and", "or", "of", "to", "in", "for", "a", "an", "is", "it", "on", "at",
        "的", "了", "和", "与", "在", "是"
    ]

    static func tokens(in raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var tokens: [String] = []
        var latin = ""
        var cjk = ""

        func flushLatin() {
            let token = latin.lowercased()
            latin = ""
            guard !token.isEmpty else { return }
            tokens.append(token)
        }

        func flushCJK() {
            let token = cjk.lowercased()
            cjk = ""
            guard !token.isEmpty else { return }
            tokens.append(token)
        }

        for character in trimmed {
            if character == "_" {
                flushCJK()
                latin.append(character)
            } else if character.isWhitespace || character.isPunctuation || character.isSymbol {
                flushLatin()
                flushCJK()
            } else if character.isCJK {
                flushLatin()
                cjk.append(character)
            } else {
                flushCJK()
                latin.append(character)
            }
        }
        flushLatin()
        flushCJK()

        if tokens.count > 1 {
            let filtered = tokens.filter { !stopwords.contains($0) }
            if !filtered.isEmpty { return filtered }
        }
        return tokens.isEmpty ? [trimmed.lowercased()] : tokens
    }

    static func score(query: String, document: KeywordDocument) -> Double {
        let foldedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !foldedQuery.isEmpty else { return 0 }
        return score(tokens: tokens(in: foldedQuery), foldedQuery: foldedQuery, fields: KeywordFields(document))
    }

    static func score(tokens queryTokens: [String], foldedQuery: String, fields: KeywordFields) -> Double {
        guard !foldedQuery.isEmpty, !queryTokens.isEmpty else { return 0 }

        let weighted: [(String, Double)] = [
            (fields.title, 1.3),
            (fields.subtitle, 0.9),
            (fields.body, 1.0),
            (fields.source, 0.6),
            (fields.tag, 0.8)
        ]

        var score = 0.0
        var hits = 0
        for token in queryTokens {
            var tokenScore = 0.0
            for (text, weight) in weighted where !text.isEmpty && text.contains(token) {
                tokenScore += weight
            }
            if tokenScore > 0 {
                hits += 1
                score += tokenScore
            }
        }
        guard hits > 0 else { return 0 }

        if hits == queryTokens.count {
            score *= 1.4
        }
        if fields.haystack.contains(foldedQuery) {
            score += 2.0
        }
        if isIdentifierQuery(foldedQuery),
           fields.haystack.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init).contains(foldedQuery) {
            score += 3.0
        }
        return score
    }

    static func score(query: String, item: ClipboardItem) -> Double {
        score(query: query, document: item.keywordDocument)
    }

    static func haystack(item: ClipboardItem) -> String {
        KeywordFields(item.keywordDocument).haystack
    }

    private static func isIdentifierQuery(_ query: String) -> Bool {
        guard !query.contains(where: \.isWhitespace), query.count >= 2 else { return false }
        return query.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
    }
}

struct KeywordFields {
    let title: String
    let subtitle: String
    let body: String
    let source: String
    let tag: String
    let haystack: String

    init(_ document: KeywordDocument) {
        title = document.title.lowercased()
        subtitle = document.subtitle?.lowercased() ?? ""
        body = String((document.body ?? "").prefix(2000)).lowercased()
        source = document.source?.lowercased() ?? ""
        tag = document.tag?.lowercased() ?? ""
        haystack = [title, subtitle, body, source, tag]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

extension KeywordDocument {
    var joinedHaystack: String { KeywordFields(self).haystack }
}

extension ClipboardItem {
    var keywordDocument: KeywordDocument {
        KeywordDocument(
            title: previewTitle,
            subtitle: previewSubtitle,
            body: plainText.map { String($0.prefix(2000)) },
            source: sourceAppName,
            tag: primaryAutoTag?.displayName
        )
    }

    var searchableText: String {
        var parts: [String] = [previewTitle]
        if let previewSubtitle, !previewSubtitle.isEmpty { parts.append(previewSubtitle) }
        if let plainText, !plainText.isEmpty {
            parts.append(String(plainText.prefix(4000)))
        }
        if let sourceAppName, !sourceAppName.isEmpty { parts.append(sourceAppName) }
        if let tag = primaryAutoTag?.displayName { parts.append(tag) }
        return parts.joined(separator: "\n")
    }
}

extension Character {
    var isCJK: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xAC00...0xD7AF, 0xF900...0xFAFF, 0x20000...0x2A6DF:
                return true
            default:
                return false
            }
        }
    }
}
