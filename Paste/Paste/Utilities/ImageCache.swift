import AppKit
import Foundation
import ImageIO

/// Decoded images and app icons, memoized. An item's image data never changes after
/// ingest, so the item id is a safe cache key; app icons are keyed by bundle id.
/// Without this, every SwiftUI body evaluation re-decoded multi-MB PNGs and asked
/// NSWorkspace for the same icons again — the main source of interaction jank.
///
/// Costs are decoded pixel bytes, not the compressed file size: a 2 MB PNG can
/// unpack to 20 MB, and a 256 MB `totalCostLimit` keyed off file size let the
/// process sit at 200 MB+ in Activity Monitor.
final class ImageCache {
    static let shared = ImageCache()

    /// Decoded bitmap budget for thumbnails + preview frames. Plenty for a shelf
    /// of cards; small enough that a menu-bar agent stays light when idle.
    static let decodedBudgetBytes = 48 * 1024 * 1024
    /// TIFF+PNG encodings used only at paste time. Recreating them is cheap next
    /// to keeping 40 uncompressed screenshots around.
    static let pasteBudgetBytes = 8 * 1024 * 1024
    static let thumbnailMaxPixel = 240
    static let previewMaxPixel = 1800

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
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private init() {
        images.countLimit = 80
        images.totalCostLimit = Self.decodedBudgetBytes
        appIcons.countLimit = 64
        pasteboardData.countLimit = 3
        pasteboardData.totalCostLimit = Self.pasteBudgetBytes
        listenForMemoryPressure()
    }

    /// `preferThumbnail` for small surfaces (cards, row badges). Detail views still
    /// downsample — a 5K capture does not need to sit fully decoded in RAM.
    func image(for item: ClipboardItem, preferThumbnail: Bool = true) -> NSImage? {
        let kind: Kind = preferThumbnail ? .thumbnail : .full
        let key = Self.key(item.id, kind) as NSString
        if let cached = images.object(forKey: key) { return cached }

        let maxPixel = preferThumbnail ? Self.thumbnailMaxPixel : Self.previewMaxPixel
        let data: Data?
        if preferThumbnail {
            data = item.thumbnailData ?? item.imageData
        } else {
            data = item.imageData ?? item.thumbnailData
        }
        guard let data, let image = downsampledImage(from: data, maxPixel: maxPixel) else { return nil }
        images.setObject(image, forKey: key, cost: Self.decodedCost(image))
        return image
    }

    /// "1920 × 1080" for image items. Reads container metadata — it must not decode
    /// the full bitmap just to label a card.
    func pixelSize(for item: ClipboardItem) -> String? {
        guard item.contentType == .image else { return nil }
        let key = (Self.key(item.id, .full) + "#size") as NSString
        if let cached = pixelSizes.object(forKey: key) { return cached as String }
        guard let data = item.imageData ?? item.thumbnailData,
              let size = Self.pixelSize(of: data) else { return nil }
        let text = "\(size.width) × \(size.height)"
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
        let key = (Self.key(id, .full) + "#paste") as NSString
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
            images.removeObject(forKey: key as NSString)
            pixelSizes.removeObject(forKey: (key + "#size") as NSString)
            pasteboardData.removeObject(forKey: (key + "#paste") as NSString)
        }
    }

    /// Drop decoded bitmaps and paste encodings. App icons stay — they are tiny and
    /// the shelf would otherwise hitch on every reopen.
    func releaseMemory() {
        images.removeAllObjects()
        pixelSizes.removeAllObjects()
        pasteboardData.removeAllObjects()
    }

    private func listenForMemoryPressure() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            self?.releaseMemory()
        }
        source.resume()
        memoryPressureSource = source
    }

    /// Thumbnail generation via ImageIO, so a missing `thumbnailData` never unpacks
    /// a 20 MB TIFF into an `NSImage` just to draw a 42 pt badge.
    private func downsampledImage(from data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        return NSImage(data: data)
    }

    static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    static func decodedCost(_ image: NSImage) -> Int {
        var pixels = 0
        for rep in image.representations {
            pixels = max(pixels, rep.pixelsWide * rep.pixelsHigh)
        }
        if pixels <= 0 {
            pixels = max(1, Int(image.size.width * image.size.height))
        }
        return max(pixels * 4, 1)
    }

    private static func key(_ id: UUID, _ kind: Kind) -> String {
        "\(id.uuidString)-\(kind.rawValue)"
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
