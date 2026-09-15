import AppKit
import Foundation

/// Decoded images and app icons, memoized. An item's image data never changes after
/// ingest, so the item id is a safe cache key; app icons are keyed by bundle id.
/// Without this, every SwiftUI body evaluation re-decoded multi-MB PNGs and asked
/// NSWorkspace for the same icons again — the main source of interaction jank.
final class ImageCache {
    static let shared = ImageCache()

    private enum Kind: String {
        case thumbnail
        case full
    }

    private let images = NSCache<NSString, NSImage>()
    private let pixelSizes = NSCache<NSString, NSString>()
    private let appIcons = NSCache<NSString, NSImage>()
    /// bundle ids whose app could not be resolved — avoid asking NSWorkspace again.
    private var missingAppIcons = Set<String>()
    private let missingLock = NSLock()
    /// Paste-ready encodings per item, so re-pasting a screenshot is instant.
    private let pasteboardData = NSCache<NSString, PasteEncodings>()

    private init() {
        images.countLimit = 300
        images.totalCostLimit = 256 * 1024 * 1024
        appIcons.countLimit = 100
        pasteboardData.countLimit = 40
    }

    /// `preferThumbnail` for small surfaces (cards, row badges), full data for detail views.
    func image(for item: ClipboardItem, preferThumbnail: Bool = true) -> NSImage? {
        let kind: Kind = preferThumbnail ? .thumbnail : .full
        let key = Self.key(item.id, kind)
        if let cached = images.object(forKey: key) { return cached }

        let data = preferThumbnail
            ? (item.thumbnailData ?? item.imageData)
            : (item.imageData ?? item.thumbnailData)
        guard let data, let image = NSImage(data: data) else { return nil }
        images.setObject(image, forKey: key, cost: data.count)
        return image
    }

    /// "1920 × 1080" for image items, decoded once per item.
    func pixelSize(for item: ClipboardItem) -> String? {
        guard item.contentType == .image else { return nil }
        let key = Self.key(item.id, .full) + "#size"
        if let cached = pixelSizes.object(forKey: key) { return cached as String }
        guard let data = item.imageData ?? item.thumbnailData,
              let image = NSImage(data: data) else { return nil }
        let w = Int(image.size.width)
        let h = Int(image.size.height)
        guard w > 0, h > 0 else { return nil }
        let text = "\(w) × \(h)"
        pixelSizes.setObject(text as NSString, forKey: key)
        return text
    }

    /// The source app's icon, or nil when the app is gone / never existed.
    /// Negative results are memoized too — a missing icon would otherwise be a
    /// synchronous NSWorkspace lookup on every card render.
    func sourceIcon(bundleID: String?) -> NSImage? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        if let cached = appIcons.object(forKey: bundleID as NSString) { return cached }
        missingLock.lock()
        let knownMissing = missingAppIcons.contains(bundleID)
        missingLock.unlock()
        guard !knownMissing else { return nil }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missingLock.lock()
            missingAppIcons.insert(bundleID)
            missingLock.unlock()
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons.setObject(icon, forKey: bundleID as NSString)
        return icon
    }

    /// TIFF + PNG encodings for pasting an image, encoded once per item id.
    /// Takes raw data (not the model) so it can run off the main thread — SwiftData
    /// models are not safe to touch from a background queue. NSCache is thread-safe.
    func pasteEncodings(id: UUID, imageData: Data) -> (tiff: Data, png: Data?)? {
        let key = Self.key(id, .full) + "#paste"
        if let cached = pasteboardData.object(forKey: key) {
            return (cached.tiff, cached.png)
        }
        guard let image = NSImage(data: imageData),
              let tiff = image.tiffRepresentation else { return nil }
        let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        let encodings = PasteEncodings(tiff: tiff, png: png)
        pasteboardData.setObject(encodings, forKey: key, cost: tiff.count + (png?.count ?? 0))
        return (tiff, png)
    }

    func remove(id: UUID) {
        for kind in [Kind.thumbnail, .full] {
            let key = Self.key(id, kind)
            images.removeObject(forKey: key)
            pixelSizes.removeObject(forKey: key + "#size")
            pasteboardData.removeObject(forKey: key + "#paste")
        }
    }

    private static func key(_ id: UUID, _ kind: Kind) -> NSString {
        "\(id.uuidString)-\(kind.rawValue)" as NSString
    }
}

/// Boxed so NSCache can hold the tuple.
private final class PasteEncodings {
    let tiff: Data
    let png: Data?

    init(tiff: Data, png: Data?) {
        self.tiff = tiff
        self.png = png
    }
}
