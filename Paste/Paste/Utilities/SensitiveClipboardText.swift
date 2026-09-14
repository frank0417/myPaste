import Foundation

enum SensitiveClipboardText {
    private static let markers = [
        "password", "passwd", "secret", "api_key", "apikey", "auth_token",
        "access_token", "private_key", "-----begin", "bearer ", "otpauth", "totp"
    ]

    /// Secrets are still keyword-searchable, but never embedded for semantic recall.
    static func shouldSkipEmbedding(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let lowered = trimmed.lowercased()
        if markers.contains(where: { lowered.contains($0) }) {
            return true
        }
        if looksLikeJWT(trimmed) { return true }
        if looksLikeHighEntropySecret(trimmed) { return true }
        return false
    }

    static func looksLikeJWT(_ text: String) -> Bool {
        let parts = text.split(separator: ".")
        guard parts.count == 3 else { return false }
        return text.hasPrefix("eyJ") || text.hasPrefix("eyj")
    }

    static func looksLikeHighEntropySecret(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        guard compact.count >= 40, compact.count <= 512 else { return false }
        guard compact.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" || $0 == "=" }) else {
            return false
        }
        if compact.contains("://") { return false }
        let unique = Set(compact.lowercased()).count
        return unique >= 16
    }
}
