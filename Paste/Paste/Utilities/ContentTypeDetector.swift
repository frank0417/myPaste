import Foundation

enum ContentTypeDetector {
    private static let urlRegex = try! NSRegularExpression(
        pattern: #"^(https?://|www\.)\S+$"#,
        options: [.caseInsensitive]
    )
    private static let hexColorRegex = try! NSRegularExpression(
        pattern: #"^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#
    )
    private static let codeHints = [
        "func ", "import ", "const ", "let ", "var ", "class ", "def ", "#!/",
        "{", "}", "=>", "console.", "SELECT ", "CREATE TABLE", "</", "<?"
    ]

    static func detect(from text: String) -> ClipboardContentType {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        if hexColorRegex.firstMatch(in: trimmed, range: range) != nil {
            return .color
        }
        if urlRegex.firstMatch(in: trimmed, range: range) != nil,
           trimmed.split(whereSeparator: \.isNewline).count == 1 {
            return .link
        }
        if looksLikeCode(trimmed) {
            return .code
        }
        if trimmed.count > 120 || trimmed.contains("\n") {
            return .snippet
        }
        return .text
    }

    static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else {
            return codeHints.contains { text.contains($0) } && text.count > 24
        }
        let hintHits = codeHints.filter { text.contains($0) }.count
        let indentLines = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        return hintHits >= 2 || (hintHits >= 1 && indentLines >= 2)
    }

    static func previewTitle(for text: String, type: ClipboardContentType) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let clipped = firstLine.count > 80 ? String(firstLine.prefix(77)) + "…" : firstLine
        switch type {
        case .link:
            return clipped.replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
        default:
            return clipped
        }
    }

    static func previewSubtitle(for text: String, type: ClipboardContentType, sourceApp: String?) -> String? {
        let charCount = text.count
        let lineCount = max(1, text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count)
        switch type {
        case .link:
            return sourceApp ?? "链接"
        case .code:
            return "\(lineCount) 行 · \(sourceApp ?? "代码")"
        case .snippet:
            return "\(charCount) 字符 · \(lineCount) 行"
        default:
            return sourceApp ?? "\(charCount) 字符"
        }
    }
}
