import CoreGraphics
import Foundation
import ImageIO
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

    /// Smallest pixel side that still gives Vision enough samples for UI type.
    /// Crops shorter than this are upscaled before recognition.
    static let minimumPreparedSide = 180
    /// Mean sRGB luminance below this is treated as a dark UI (light glyphs).
    static let darkLuminanceThreshold: CGFloat = 0.45
    /// Downsample size for the darkness probe — a 16×16 average is enough.
    static let luminanceSampleSize = 16

    /// Overlay OCR should send the cropped `CGImage` here. PNG round-trips and
    /// `.accurate` (document) recognition often return nothing on UI screenshots.
    static func recognize(cgImage: CGImage) -> String? {
        recognize(preparedCGImage: preparedImage(from: cgImage))
    }

    /// Vision on a bitmap that `preparedImage(from:)` already copied. Overlay OCR
    /// must copy on the main thread first: the freeze is IOSurface-backed, and
    /// reading it from a detached task while the canvas draws often yields nothing.
    ///
    /// Dark UIs (light glyphs on black) are inverted first: Vision is tuned for
    /// dark ink on paper and often returns nothing on a terminal or dark IDE.
    static func recognize(preparedCGImage: CGImage) -> String? {
        let inverted = invertedImage(from: preparedCGImage)
        let images: [CGImage]
        if isDark(preparedCGImage), let inverted {
            images = [inverted, preparedCGImage]
        } else if let inverted {
            images = [preparedCGImage, inverted]
        } else {
            images = [preparedCGImage]
        }
        for image in images {
            if let text = recognizeVariants(on: image) {
                return text
            }
        }
        return nil
    }

    private static func recognizeVariants(on image: CGImage) -> String? {
        let attempts: [(VNRequestTextRecognitionLevel, [String])] = [
            (.fast, languages),
            (.accurate, languages),
            (.fast, []),
            (.accurate, [])
        ]
        for (level, langs) in attempts {
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            if let text = run(handler: handler, level: level, languages: langs) {
                return text
            }
        }
        return nil
    }

    /// Copy into a disconnected sRGB bitmap so ScreenCaptureKit IOSurface / BGRA
    /// crops (and tiny UI type) are something Vision will actually read.
    static func preparedImage(from image: CGImage) -> CGImage {
        let minSide = min(image.width, image.height)
        let scale = (minSide > 0 && minSide < minimumPreparedSide) ? 2 : 1
        let width = max(1, image.width * scale)
        let height = max(1, image.height * scale)
        guard let ctx = rgbContext(width: width, height: height) else { return image }
        ctx.interpolationQuality = scale > 1 ? .high : .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? image
    }

    /// Recolor light-on-dark UI as dark ink on paper. Alpha is left alone so a
    /// fully opaque screenshot does not become a transparent hole.
    static func invertedImage(from image: CGImage) -> CGImage? {
        let width = max(1, image.width)
        let height = max(1, image.height)
        guard let ctx = rgbContext(width: width, height: height) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        invertRGBKeepingAlpha(in: ctx, width: width, height: height)
        return ctx.makeImage()
    }

    static func isDark(_ image: CGImage) -> Bool {
        guard let mean = meanLuminance(of: image) else { return false }
        return mean < darkLuminanceThreshold
    }

    /// Rec. 709 luma, 0…1, from a tiny downsample of the freeze.
    static func meanLuminance(of image: CGImage) -> CGFloat? {
        let side = luminanceSampleSize
        guard let ctx = rgbContext(width: side, height: side) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return nil }
        let rowBytes = ctx.bytesPerRow
        var sum: Double = 0
        var count = 0
        for y in 0..<side {
            let row = data.advanced(by: y * rowBytes)
            for x in 0..<side {
                let pixel = row.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self)
                let r = Double(pixel[0])
                let g = Double(pixel[1])
                let b = Double(pixel[2])
                sum += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return CGFloat(sum / Double(count) / 255)
    }

    private static func rgbContext(width: Int, height: Int) -> CGContext? {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        // byteOrder32Big + premultipliedLast is RGBA in memory on every endianness,
        // so the invert / luminance walks can treat byte 3 as alpha.
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    }

    private static func invertRGBKeepingAlpha(in ctx: CGContext, width: Int, height: Int) {
        guard let data = ctx.data else { return }
        let rowBytes = ctx.bytesPerRow
        for y in 0..<height {
            let row = data.advanced(by: y * rowBytes)
            for x in 0..<width {
                let pixel = row.advanced(by: x * 4).assumingMemoryBound(to: UInt8.self)
                pixel[0] = 255 &- pixel[0]
                pixel[1] = 255 &- pixel[1]
                pixel[2] = 255 &- pixel[2]
            }
        }
    }

    /// Runs synchronously on whatever queue calls it — the capture pipeline's
    /// background queue. `nil` when the image holds no readable text.
    static func recognize(imageData: Data) -> String? {
        if let cgImage = cgImage(from: imageData) {
            return recognize(cgImage: cgImage)
        }
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        return run(handler: handler, level: .fast, languages: languages)
            ?? run(handler: VNImageRequestHandler(data: imageData, options: [:]), level: .accurate, languages: languages)
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func run(
        handler: VNImageRequestHandler,
        level: VNRequestTextRecognitionLevel,
        languages: [String]
    ) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.usesLanguageCorrection = (level == .accurate)
        // `.fast` is for sparse UI chrome; do not drop small labels. Accurate
        // (document) recognition still ignores specks.
        request.minimumTextHeight = (level == .fast) ? 0 : 0.008
        if languages.isEmpty {
            request.automaticallyDetectsLanguage = true
        } else {
            request.recognitionLanguages = languages
        }

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
