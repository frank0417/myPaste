import AppKit
import Foundation
import Combine
import CryptoKit

/// Watches the system pasteboard and emits normalized clipboard payloads.
@MainActor
final class ClipboardMonitor: ObservableObject {
    static let shared = ClipboardMonitor()

    @Published private(set) var latestChangeCount: Int = 0
    @Published private(set) var isPaused: Bool = false

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var ignoreNextChange: Bool = false
    private let pasteboard = NSPasteboard.general
    /// Image decode + hashing + thumbnail rendering happen here, never on main.
    private let captureQueue = DispatchQueue(label: "com.mypaste.PasteNest.capture", qos: .userInitiated)
    private var captureInFlight = false
    /// Set when the pasteboard changed again while a capture was running.
    private var captureAgainPending = false

    var onNewItem: ((CapturedClipboardPayload) -> Void)?

    private init() {}

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        // Register only for .common so ticks keep firing during menu tracking / panel use.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            let monitor = self
            Task { @MainActor in
                monitor?.poll()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    /// Call before writing to the pasteboard so we do not re-capture our own paste.
    func ignoreNextPasteboardChange() {
        ignoreNextChange = true
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        guard !isPaused else { return }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        latestChangeCount = changeCount

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        // One capture at a time; a change that lands mid-capture re-runs once after,
        // so rapid copies coalesce instead of queueing up stale work.
        guard !captureInFlight else {
            captureAgainPending = true
            return
        }
        startCapture()
    }

    private func startCapture() {
        captureInFlight = true

        // Read the source app now, on main, while it is still the app that copied.
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let sourceName = sourceApp?.localizedName
        let sourceBundle = sourceApp?.bundleIdentifier

        captureQueue.async { [weak self] in
            let payload = Self.capture(
                from: NSPasteboard.general,
                sourceName: sourceName,
                sourceBundle: sourceBundle
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.captureInFlight = false
                if let payload {
                    self.onNewItem?(payload)
                }
                if self.captureAgainPending {
                    self.captureAgainPending = false
                    // Do not go through poll(): the change count was already consumed,
                    // but the pasteboard holds newer content than the capture read.
                    self.startCapture()
                }
            }
        }
    }

    private nonisolated static func resolvedContentType(plain: String, rtf: Data?) -> ClipboardContentType {
        var type = ContentTypeDetector.detect(from: plain)
        if rtf != nil, type == .text || type == .snippet {
            type = .richText
        }
        return type
    }

    /// Reads whatever the pasteboard currently holds. Runs on `captureQueue`; the
    /// source app is captured by the caller on the main thread, where NSWorkspace
    /// belongs and while it still reflects the copying app.
    nonisolated static func capture(
        from pasteboard: NSPasteboard,
        sourceName: String? = nil,
        sourceBundle: String? = nil
    ) -> CapturedClipboardPayload? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            let names = urls.map(\.lastPathComponent).joined(separator: ", ")
            let hash = hashString(urls.map(\.absoluteString).joined(separator: "\n"))
            return CapturedClipboardPayload(
                contentType: .file,
                plainText: names,
                imageData: nil,
                richTextData: nil,
                fileURLs: urls,
                contentHash: hash,
                previewTitle: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) 个文件",
                previewSubtitle: urls.first?.deletingLastPathComponent().path,
                colorHex: nil,
                sourceAppName: sourceName,
                sourceAppBundleID: sourceBundle
            )
        }

        if let image = NSImage(pasteboard: pasteboard),
           let stored = storedImageData(from: pasteboard, image: image) {
            let hash = hashData(stored)
            let thumb = thumbnailData(from: image, maxSize: 240)
            let pixels = pixelSize(of: image)
            return CapturedClipboardPayload(
                contentType: .image,
                plainText: nil,
                imageData: stored,
                richTextData: nil,
                fileURLs: [],
                contentHash: hash,
                previewTitle: "图片 \(pixels.width)×\(pixels.height)",
                previewSubtitle: sourceName,
                colorHex: nil,
                sourceAppName: sourceName,
                sourceAppBundleID: sourceBundle,
                thumbnailData: thumb
            )
        }

        if let color = readColor(from: pasteboard) {
            let hex = color.toHexString()
            return CapturedClipboardPayload(
                contentType: .color,
                plainText: hex,
                imageData: nil,
                richTextData: nil,
                fileURLs: [],
                contentHash: hashString(hex),
                previewTitle: hex,
                previewSubtitle: "颜色",
                colorHex: hex,
                sourceAppName: sourceName,
                sourceAppBundleID: sourceBundle
            )
        }

        let plain = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rtf = pasteboard.data(forType: .rtf)

        guard let plain, !plain.isEmpty else { return nil }

        let type = resolvedContentType(plain: plain, rtf: rtf)
        let title = ContentTypeDetector.previewTitle(for: plain, type: type)
        let subtitle = ContentTypeDetector.previewSubtitle(for: plain, type: type, sourceApp: sourceName)

        return CapturedClipboardPayload(
            contentType: type,
            plainText: plain,
            imageData: nil,
            richTextData: rtf,
            fileURLs: [],
            contentHash: hashString(plain),
            previewTitle: title,
            previewSubtitle: subtitle,
            colorHex: type == .color ? plain : nil,
            sourceAppName: sourceName,
            sourceAppBundleID: sourceBundle
        )
    }

    private nonisolated static func readColor(from pasteboard: NSPasteboard) -> NSColor? {
        if let colors = pasteboard.readObjects(forClasses: [NSColor.self], options: nil) as? [NSColor],
           let color = colors.first {
            return color
        }
        return nil
    }

    /// Prefer the pasteboard's own PNG; never persist `tiffRepresentation`.
    /// A Retina screenshot's TIFF is typically 15–40 MB, the PNG 1–4 MB.
    nonisolated static func storedImageData(from pasteboard: NSPasteboard, image: NSImage) -> Data? {
        if let png = pasteboard.data(forType: .png), png.count > 32 {
            if png.count <= ClipboardImageStorage.maxPreferredPNGBytes, !exceedsMaxPixelEdge(image) {
                return png
            }
            return compactImageData(from: image) ?? png
        }
        return compactImageData(from: image)
    }

    /// Re-encode a previously stored blob if it is an uncompressed TIFF (or just huge).
    nonisolated static func compactedImageData(_ data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        guard let compacted = compactImageData(from: image) else { return nil }
        guard compacted.count < data.count else { return nil }
        return compacted
    }

    nonisolated static func shouldCompactStoredImage(_ data: Data) -> Bool {
        if isTIFF(data) { return data.count >= ClipboardImageStorage.compactIfLargerThanBytes }
        return data.count >= ClipboardImageStorage.alwaysCompactIfLargerThanBytes
    }

    nonisolated static func isTIFF(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let b0 = data[data.startIndex]
        let b1 = data[data.startIndex.advanced(by: 1)]
        let b2 = data[data.startIndex.advanced(by: 2)]
        let b3 = data[data.startIndex.advanced(by: 3)]
        // II*\0 little-endian or MM\0* big-endian
        return (b0 == 0x49 && b1 == 0x49 && b2 == 0x2A && b3 == 0x00)
            || (b0 == 0x4D && b1 == 0x4D && b2 == 0x00 && b3 == 0x2A)
    }

    nonisolated static func compactImageData(from image: NSImage) -> Data? {
        guard let rep = rasterized(image, maxEdge: ClipboardImageStorage.maxStoredPixelEdge) else { return nil }
        if let png = rep.representation(using: .png, properties: [:]),
           png.count <= ClipboardImageStorage.maxPreferredPNGBytes {
            return png
        }
        return rep.representation(
            using: .jpeg,
            properties: [.compressionFactor: ClipboardImageStorage.jpegQuality]
        ) ?? rep.representation(using: .png, properties: [:])
    }

    nonisolated static func exceedsMaxPixelEdge(_ image: NSImage) -> Bool {
        let size = pixelSize(of: image)
        return CGFloat(max(size.width, size.height)) > ClipboardImageStorage.maxStoredPixelEdge
    }

    nonisolated static func pixelSize(of image: NSImage) -> (width: Int, height: Int) {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        return (max(1, Int(image.size.width)), max(1, Int(image.size.height)))
    }

    nonisolated static func rasterized(_ image: NSImage, maxEdge: CGFloat) -> NSBitmapImageRep? {
        let pixels = pixelSize(of: image)
        let longest = CGFloat(max(pixels.width, pixels.height))
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let width = max(1, Int((CGFloat(pixels.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(pixels.height) * scale).rounded()))
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Shared with `ScreenshotService` so captures get the same shelf thumbnails.
    nonisolated static func thumbnailData(from image: NSImage, maxSize: CGFloat) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(maxSize / size.width, maxSize / size.height, 1)
        let target = NSSize(width: size.width * scale, height: size.height * scale)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75])
    }

    /// One pasteboard item carrying both representations of an image: the picture
    /// plus, when we have it, the text recognized inside it. The receiving app asks
    /// for the type it wants, so a text field gets the text and an image view the png.
    nonisolated static func imagePasteboardItem(imageData: Data, text: String?) -> NSPasteboardItem? {
        guard let image = NSImage(data: imageData), let tiff = image.tiffRepresentation else { return nil }
        let item = NSPasteboardItem()
        // Some apps only read tiff, so offer both encodings at paste time. History
        // stores PNG/JPEG; this TIFF is transient and not written back to the store.
        item.setData(tiff, forType: .tiff)
        if let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        if let text, !text.isEmpty {
            item.setString(text, forType: .string)
        }
        return item
    }

    nonisolated static func hashString(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func hashData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Limits for what we persist. Kept off `ClipboardMonitor` so the `@MainActor`
/// class does not isolate the numbers from `nonisolated` capture helpers.
enum ClipboardImageStorage {
    /// Longest edge stored for a copied image. 5K captures still paste; they just
    /// don't sit in RAM as a 40 MB uncompressed TIFF.
    static let maxStoredPixelEdge: CGFloat = 2560
    /// PNG stays lossless up to this size; larger (photos) become JPEG.
    static let maxPreferredPNGBytes = 1_500_000
    /// TIFF payloads this large are worth recompressing on a later sweep.
    static let compactIfLargerThanBytes = 800_000
    /// Any encoding this large is worth another pass, TIFF or not.
    static let alwaysCompactIfLargerThanBytes = 3_000_000
    static let jpegQuality: CGFloat = 0.78
}

struct CapturedClipboardPayload {
    let contentType: ClipboardContentType
    let plainText: String?
    let imageData: Data?
    let richTextData: Data?
    let fileURLs: [URL]
    let contentHash: String
    let previewTitle: String
    let previewSubtitle: String?
    let colorHex: String?
    let sourceAppName: String?
    let sourceAppBundleID: String?
    var thumbnailData: Data? = nil
}

extension NSColor {
    func toHexString() -> String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
