import Foundation
import Vision

/// On-device OCR for captured images, via Vision. Nothing leaves the Mac.
enum TextRecognizer {
    /// Chinese first: Vision picks its script models from this order, and a
    /// Latin-first list misses 简体 / 繁体 text in mixed screenshots.
    static let languages = ["zh-Hans", "zh-Hant", "en-US"]

    /// Two observations whose vertical centres are within this fraction of the
    /// image height belong to the same visual line.
    static let lineTolerance: CGFloat = 0.014

    /// A single recognized line, in normalized Vision coordinates (origin bottom-left).
    struct Fragment {
        let text: String
        let midY: CGFloat
        let minX: CGFloat
    }

    /// Runs synchronously on whatever queue calls it — the capture pipeline's
    /// background queue. `nil` when the image holds no readable text.
    static func recognize(imageData: Data) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        let fragments = (request.results ?? []).compactMap { observation -> Fragment? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let box = observation.boundingBox
            return Fragment(text: text, midY: box.midY, minX: box.minX)
        }
        return assemble(fragments)
    }

    /// Vision returns observations without a guaranteed order, so rebuild reading
    /// order: top to bottom, then left to right within each line.
    static func assemble(_ fragments: [Fragment]) -> String? {
        guard !fragments.isEmpty else { return nil }

        let ordered = fragments.sorted { lhs, rhs in
            if abs(lhs.midY - rhs.midY) > lineTolerance {
                // Normalized coordinates start at the bottom, so larger y is higher up.
                return lhs.midY > rhs.midY
            }
            return lhs.minX < rhs.minX
        }

        var lines: [[Fragment]] = []
        for fragment in ordered {
            if let last = lines.last?.last, abs(last.midY - fragment.midY) <= lineTolerance {
                lines[lines.count - 1].append(fragment)
            } else {
                lines.append([fragment])
            }
        }

        let text = lines
            .map { line in joinFragments(line.map(\.text)) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Side-by-side fragments need a separator, except between two CJK characters:
    /// Chinese reads wrong with spaces injected into it, while a CJK/Latin boundary
    /// normally does carry one.
    static func joinFragments(_ pieces: [String]) -> String {
        guard var result = pieces.first else { return "" }
        for piece in pieces.dropFirst() {
            let bothCJK = isCJK(result.last) && isCJK(piece.first)
            result += bothCJK ? piece : " " + piece
        }
        return result
    }

    static func isCJK(_ character: Character?) -> Bool {
        guard let scalar = character?.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3000...0x303F, // CJK punctuation
             0x3400...0x4DBF, // extension A
             0x4E00...0x9FFF, // unified ideographs
             0xF900...0xFAFF, // compatibility ideographs
             0xFF00...0xFFEF: // fullwidth forms
            return true
        default:
            return false
        }
    }

    /// Whitespace does not count, so "识别 42 字" reflects actual content.
    static func characterCount(of text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if !character.isWhitespace { count += 1 }
        }
    }
}
