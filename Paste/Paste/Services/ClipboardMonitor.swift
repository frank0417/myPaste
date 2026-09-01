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

    var onNewItem: ((CapturedClipboardPayload) -> Void)?

    private init() {}

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pause() { isPaused = true }
    func resume() { isPaused = false }

    /// Call before programmatically writing to the pasteboard so we do not re-capture our own paste.
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

        if let payload = Self.capture(from: pasteboard) {
            onNewItem?(payload)
        }
    }

    static func capture(from pasteboard: NSPasteboard) -> CapturedClipboardPayload? {
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let sourceName = sourceApp?.localizedName
        let sourceBundle = sourceApp?.bundleIdentifier

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
           let tiff = image.tiffRepresentation {
            let hash = hashData(tiff)
            let thumb = thumbnailData(from: image, maxSize: 240)
            return CapturedClipboardPayload(
                contentType: .image,
                plainText: nil,
                imageData: tiff,
                richTextData: nil,
                fileURLs: [],
                contentHash: hash,
                previewTitle: "图片 \(Int(image.size.width))×\(Int(image.size.height))",
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

        let type = ContentTypeDetector.detect(from: plain)
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

    private static func readColor(from pasteboard: NSPasteboard) -> NSColor? {
        if let colors = pasteboard.readObjects(forClasses: [NSColor.self], options: nil) as? [NSColor],
           let color = colors.first {
            return color
        }
        return nil
    }

    private static func thumbnailData(from image: NSImage, maxSize: CGFloat) -> Data? {
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

    static func hashString(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func hashData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
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
