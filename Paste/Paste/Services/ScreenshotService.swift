import AppKit
import Combine
import CoreGraphics
import Foundation
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Apple's capture tool. Kept outside the main-actor type so the background worker
/// can read it.
private let screenCaptureToolPath = "/usr/sbin/screencapture"

/// What part of the screen a capture grabs.
enum ScreenshotMode: String, CaseIterable, Identifiable {
    case region
    case window
    case fullScreen

    var id: String { rawValue }

    var title: String { ScreenshotL10n.modeTitle(self) }

    var systemImage: String {
        switch self {
        case .region: return "viewfinder"
        case .window: return "macwindow"
        case .fullScreen: return "display"
        }
    }

    /// Shown under the preview title in the history.
    var subtitle: String { ScreenshotL10n.modeSubtitle(self) }

    /// Flags for `/usr/sbin/screencapture`. The interactive modes draw the system
    /// crosshair / window picker, so Esc cancels and Space switches modes as usual.
    func arguments(output: String) -> [String] {
        switch self {
        case .region:
            return ["-i", "-t", "png", output]
        case .window:
            return ["-i", "-W", "-t", "png", output]
        case .fullScreen:
            // -m keeps it to the display with the menu bar; without it a multi-display
            // setup writes one file per screen and we would only ever read the first.
            return ["-m", "-t", "png", output]
        }
    }
}

/// Captures a frozen screenshot, then opens a custom overlay so the user can crop
/// and annotate before the image is filed in clipboard history.
///
/// Pixels come from ScreenCaptureKit (with `CGDisplayCreateImage` as fallback).
/// `/usr/sbin/screencapture` is only used when both grabbers fail, typically in
/// environments where Screen Recording has not been granted yet.
@MainActor
final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()

    /// Set by `AppDelegate` to the store that owns pasteboard monitoring, so a
    /// screenshot lands in history exactly once.
    var onCaptured: ((CapturedClipboardPayload) -> Void)?
    /// Set by `AppDelegate`: text read out of a capture after the fact, keyed by the
    /// capture's content hash, so the store can attach it to the right item.
    var onRecognized: ((_ contentHash: String, _ text: String) -> Void)?

    @Published private(set) var isCapturing = false

    /// The most recent plain capture, kept so the action bar under the pointer can
    /// still read its text or save it after the pipeline has moved on.
    private struct LastCapture {
        let contentHash: String
        let pngData: Data
        let title: String
        let thumbnail: NSImage?
    }
    private var lastCapture: LastCapture?

    private let queue = DispatchQueue(label: "com.mypaste.PasteNest.screenshot")

    private init() {}

    /// `recognizeText` splits the two purposes: a plain capture keeps the picture and
    /// never runs OCR (the user can still ask for 识别文字 on the card later); a 识字
    /// capture keeps only the recognized text and drops the image entirely. The user
    /// picks per capture from the menus; the hotkey always takes a plain capture.
    func capture(_ mode: ScreenshotMode, recognizeText: Bool = false) {
        guard !isCapturing, !ScreenshotOverlayController.shared.isActive else { return }
        isCapturing = true

        // Our own windows must not end up in the shot; bring them back afterwards.
        let restorePanel = StatusItemController.shared.isPanelVisible
        let restoreMain = StatusItemController.shared.isMainWindowVisible
        if restorePanel {
            StatusItemController.shared.hidePanel()
        }
        if restoreMain {
            StatusItemController.shared.hideMainWindow()
        }
        requestScreenRecordingAccessIfNeeded()

        let delayNs: UInt64 = (restorePanel || restoreMain) ? 250_000_000 : 40_000_000
        Task { [self] in
            try? await Task.sleep(nanoseconds: delayNs)
            let frames = await ScreenshotGrabber.captureAllScreens()
            await MainActor.run {
                if frames.isEmpty {
                    self.captureWithSystemTool(
                        mode: mode,
                        recognizeText: recognizeText,
                        restorePanel: restorePanel,
                        restoreMain: restoreMain
                    )
                    return
                }
                ScreenshotOverlayController.shared.present(
                    frames: frames,
                    mode: mode,
                    recognizeText: recognizeText
                ) { outcome in
                    switch outcome {
                    case .cancelled:
                        self.isCapturing = false
                        self.restoreWindows(panel: restorePanel, main: restoreMain)
                    case .captured(let png, let rawPNG):
                        self.finishOverlayCapture(
                            mode: mode,
                            png: png,
                            rawPNG: rawPNG,
                            recognizeText: recognizeText,
                            restorePanel: restorePanel,
                            restoreMain: restoreMain
                        )
                    }
                }
            }
        }
    }

    /// Fallback when ScreenCaptureKit and CGDisplayCreateImage both fail: the
    /// system picker still works in non-sandboxed builds.
    private func captureWithSystemTool(
        mode: ScreenshotMode,
        recognizeText: Bool,
        restorePanel: Bool,
        restoreMain: Bool
    ) {
        let output = Self.makeOutputURL()
        let arguments = mode.arguments(output: output.path)
        queue.async { [self] in
            let status = Self.runScreenCapture(arguments)
            let data = Self.readPNG(at: output)
            let text = data.flatMap { recognizeText ? TextRecognizer.recognize(imageData: $0) : nil }
            Task { @MainActor in
                self.finish(
                    mode: mode,
                    data: data,
                    text: text,
                    recognizeText: recognizeText,
                    status: status,
                    restorePanel: restorePanel,
                    restoreMain: restoreMain,
                    showActionBar: true
                )
            }
        }
    }

    private func finishOverlayCapture(
        mode: ScreenshotMode,
        png: Data,
        rawPNG: Data,
        recognizeText: Bool,
        restorePanel: Bool,
        restoreMain: Bool
    ) {
        if recognizeText {
            queue.async { [self] in
                let text = TextRecognizer.recognize(imageData: rawPNG)
                Task { @MainActor in
                    self.finish(
                        mode: mode,
                        data: png,
                        text: text,
                        recognizeText: true,
                        status: 0,
                        restorePanel: restorePanel,
                        restoreMain: restoreMain,
                        showActionBar: false
                    )
                }
            }
            return
        }
        finish(
            mode: mode,
            data: png,
            text: nil,
            recognizeText: false,
            status: 0,
            restorePanel: restorePanel,
            restoreMain: restoreMain,
            showActionBar: false
        )
    }

    private func finish(
        mode: ScreenshotMode,
        data: Data?,
        text: String?,
        recognizeText: Bool,
        status: Int32,
        restorePanel: Bool,
        restoreMain: Bool = false,
        showActionBar: Bool = true
    ) {
        isCapturing = false

        guard let data else {
            // No file means the user pressed Esc — unless macOS never let us capture
            // at all, which is a permission problem worth explaining.
            if !Self.hasScreenRecordingAccess {
                presentPermissionAlert()
            } else if status != 0 && status != 1 {
                presentFailureAlert(status: status)
            }
            restoreWindows(panel: restorePanel, main: restoreMain)
            return
        }

        if recognizeText {
            finishTextCapture(mode: mode, text: text, restorePanel: restorePanel, restoreMain: restoreMain)
            return
        }

        guard let payload = Self.payload(mode: mode, pngData: data) else {
            restoreWindows(panel: restorePanel, main: restoreMain)
            return
        }
        writeImageToPasteboard(data)
        onCaptured?(payload)
        let thumbnail = payload.thumbnailData.flatMap(NSImage.init(data:))
        lastCapture = LastCapture(
            contentHash: payload.contentHash,
            pngData: data,
            title: payload.previewTitle,
            thumbnail: thumbnail
        )
        restoreWindows(panel: restorePanel, main: restoreMain)
        if showActionBar {
            // System-picker fallback: the strip under the pointer still offers OCR
            // and download, since that path has no annotation toolbar.
            ScreenshotActionBar.shared.show(
                thumbnail: thumbnail,
                title: ScreenshotL10n.copiedTitle(payload.previewTitle),
                anchor: NSEvent.mouseLocation,
                actions: .init(
                    recognizeText: { [self] in recognizeLastCapture() },
                    save: { [self] in saveLastCapture() }
                )
            )
        } else {
            ScreenshotHUD.shared.show(thumbnail: thumbnail, title: payload.previewTitle, detail: ScreenshotL10n.string(.imageCopied))
        }
    }

    private func restoreWindows(panel: Bool, main: Bool) {
        if panel {
            StatusItemController.shared.showPanel()
        } else if main {
            StatusItemController.shared.showMainWindow()
        }
    }

    /// Reads the text in the capture that just landed, puts it on the pasteboard and
    /// hands it to the store to attach to the image item. The picture stays.
    func recognizeLastCapture() {
        guard let capture = lastCapture else { return }
        queue.async { [self] in
            let text = TextRecognizer.recognize(imageData: capture.pngData)
            Task { @MainActor in
                guard let text, !text.isEmpty else {
                    ScreenshotHUD.shared.show(thumbnail: capture.thumbnail, title: capture.title, detail: ScreenshotL10n.string(.ocrEmpty))
                    return
                }
                ClipboardMonitor.shared.ignoreNextPasteboardChange()
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                self.onRecognized?(capture.contentHash, text)
                ScreenshotHUD.shared.show(
                    thumbnail: capture.thumbnail,
                    title: capture.title,
                    detail: Self.hudDetail(text: text)
                )
            }
        }
    }

    /// Offers the capture as a PNG through a save panel. Guideline 2.4.5(i) requires
    /// that MAS builds not claim unprompted Downloads access; user-selected
    /// read-write is enough for NSSavePanel.
    func saveLastCapture() {
        guard let capture = lastCapture else { return }
        Self.saveImage(capture.pngData, suggestedName: Self.downloadFileName(), thumbnail: capture.thumbnail)
    }

    static func downloadFileName(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return ScreenshotL10n.downloadFileName(stamp: formatter.string(from: now))
    }

    /// Shared by the action bar and the history cards' 保存图片 action.
    /// Always uses NSSavePanel so the binary only needs `files.user-selected.read-write`.
    static func saveImage(_ pngData: Data, suggestedName: String, thumbnail: NSImage? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if (try? pngData.write(to: url, options: .atomic)) != nil {
            ScreenshotHUD.shared.show(thumbnail: thumbnail, title: url.lastPathComponent, detail: ScreenshotL10n.string(.saved))
        }
    }

    /// A 识字 capture keeps only the words: the image is discarded, the text goes to
    /// the pasteboard and into history as a normal text item.
    private func finishTextCapture(mode: ScreenshotMode, text: String?, restorePanel: Bool, restoreMain: Bool = false) {
        guard let text, !text.isEmpty else {
            restoreWindows(panel: restorePanel, main: restoreMain)
            if !restorePanel && !restoreMain {
                ScreenshotHUD.shared.show(thumbnail: nil, title: ScreenshotL10n.string(.textCapture), detail: ScreenshotL10n.string(.ocrEmpty))
            }
            return
        }
        ClipboardMonitor.shared.ignoreNextPasteboardChange()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let payload = Self.textPayload(mode: mode, text: text)
        onCaptured?(payload)
        restoreWindows(panel: restorePanel, main: restoreMain)
        if !restorePanel && !restoreMain {
            ScreenshotHUD.shared.show(
                thumbnail: nil,
                title: ScreenshotL10n.string(.textCapture),
                detail: Self.hudDetail(text: text)
            )
        }
    }

    /// Screenshots go on the pasteboard too, so ⌘V works right after capturing.
    private func writeImageToPasteboard(_ pngData: Data) {
        guard let item = ClipboardMonitor.imagePasteboardItem(imageData: pngData, text: nil) else { return }
        ClipboardMonitor.shared.ignoreNextPasteboardChange()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    static func hudDetail(text: String?) -> String {
        guard let text else { return ScreenshotL10n.string(.ocrEmpty) }
        return ScreenshotL10n.hudRecognizedCopied(TextRecognizer.characterCount(of: text))
    }

    /// macOS gates screen capture behind 屏幕录制 (TCC), including captures made by
    /// the `screencapture` tool on our behalf.
    static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Prompts, then opens the pane so the user can grant access from Settings.
    static func requestScreenRecordingAccess() {
        _ = CGRequestScreenCaptureAccess()
        openScreenRecordingSettings()
    }

    /// Prompts once so PasteNest shows up in 隐私与安全性 → 屏幕录制.
    private func requestScreenRecordingAccessIfNeeded() {
        guard !Self.hasScreenRecordingAccess else { return }
        _ = CGRequestScreenCaptureAccess()
    }

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ScreenshotL10n.string(.permissionTitle)
        alert.informativeText = ScreenshotL10n.string(.permissionBody)
        alert.addButton(withTitle: ScreenshotL10n.string(.openSystemSettings))
        alert.addButton(withTitle: ScreenshotL10n.string(.later))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Self.openScreenRecordingSettings()
        }
    }

    private func presentFailureAlert(status: Int32) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = ScreenshotL10n.string(.captureFailed)
        alert.informativeText = ScreenshotL10n.captureFailedBody(status: status)
        alert.addButton(withTitle: ScreenshotL10n.string(.ok))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    static func openScreenRecordingSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private nonisolated static func makeOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteNest-Screenshot-\(UUID().uuidString)")
            .appendingPathExtension("png")
    }

    /// Runs off the main actor: `waitUntilExit` blocks until the user finishes
    /// selecting, which can be many seconds.
    private nonisolated static func runScreenCapture(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: screenCaptureToolPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// `nil` for a cancelled capture: `screencapture` then leaves no file behind
    /// (or an empty one). The temp file is always removed.
    private nonisolated static func readPNG(at url: URL) -> Data? {
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return data
    }

    static func payload(mode: ScreenshotMode, pngData: Data) -> CapturedClipboardPayload? {
        guard let image = NSImage(data: pngData) else { return nil }
        let size = pixelSize(of: image)
        return CapturedClipboardPayload(
            contentType: .image,
            plainText: nil,
            imageData: pngData,
            richTextData: nil,
            fileURLs: [],
            contentHash: ClipboardMonitor.hashData(pngData),
            previewTitle: previewTitle(width: size.width, height: size.height),
            previewSubtitle: mode.subtitle,
            colorHex: nil,
            sourceAppName: ScreenshotL10n.string(.sourceScreenshot),
            sourceAppBundleID: nil,
            thumbnailData: ClipboardMonitor.thumbnailData(from: image, maxSize: 240)
        )
    }

    /// A 识字 result is a plain text item: no image is kept, and the usual type
    /// detection still applies, so a recognized URL lands as a link.
    static func textPayload(mode: ScreenshotMode, text: String) -> CapturedClipboardPayload {
        let type = ContentTypeDetector.detect(from: text)
        return CapturedClipboardPayload(
            contentType: type,
            plainText: text,
            imageData: nil,
            richTextData: nil,
            fileURLs: [],
            contentHash: ClipboardMonitor.hashString(text),
            previewTitle: ContentTypeDetector.previewTitle(for: text, type: type),
            previewSubtitle: ScreenshotL10n.textCaptureSubtitle(TextRecognizer.characterCount(of: text)),
            colorHex: nil,
            sourceAppName: ScreenshotL10n.string(.textCapture),
            sourceAppBundleID: nil
        )
    }

    /// Searchable on its own: typing 截图 finds every capture.
    static func previewTitle(width: Int, height: Int) -> String {
        ScreenshotL10n.previewTitle(width: width, height: height)
    }

    /// `NSImage.size` is in points; the bitmap rep carries the Retina pixel count.
    private static func pixelSize(of image: NSImage) -> (width: Int, height: Int) {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        return (Int(image.size.width), Int(image.size.height))
    }
}

enum ScreenshotGrabber {
    struct Frame {
        let screen: NSScreen
        let image: NSImage
        let cgImage: CGImage
        let scale: CGFloat
        let windows: [CGRect]
    }

    static func captureAllScreens() async -> [Frame] {
        let windows = windowRectsByScreen()
        let kitContent = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var frames: [Frame] = []
        for screen in NSScreen.screens {
            let cgImage: CGImage?
            if let kitContent {
                cgImage = try? await captureWithKit(screen: screen, content: kitContent)
            } else {
                cgImage = nil
            }
            guard let cgImage = cgImage ?? CGDisplayCreateImage(screen.displayID) else { continue }
            let image = nsImage(from: cgImage, pointSize: screen.frame.size)
            let scale = CGFloat(cgImage.width) / max(screen.frame.width, 1)
            frames.append(
                Frame(
                    screen: screen,
                    image: image,
                    cgImage: cgImage,
                    scale: scale,
                    windows: windows[screen.displayID] ?? []
                )
            )
        }
        return frames
    }

    private static func captureWithKit(screen: NSScreen, content: SCShareableContent) async throws -> CGImage {
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw NSError(domain: "PasteNest.Screenshot", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Display not found"
            ])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let pixels = ScreenshotLayout.outputPixelSize(
            contentRect: filter.contentRect.size,
            pointPixelScale: CGFloat(filter.pointPixelScale),
            screenPoints: screen.frame.size,
            backingScale: screen.backingScaleFactor
        )
        let config = SCStreamConfiguration()
        config.width = pixels.width
        config.height = pixels.height
        config.showsCursor = false
        config.scalesToFit = true
        if #available(macOS 14.2, *) {
            config.captureResolution = .best
        }
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func nsImage(from cgImage: CGImage, pointSize: CGSize) -> NSImage {
        let image = NSImage(size: pointSize)
        image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        return image
    }

    /// Layer-0 on-screen windows, converted into each display's flipped canvas space.
    static func windowRectsByScreen() -> [CGDirectDisplayID: [CGRect]] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        var result: [CGDirectDisplayID: [CGRect]] = [:]
        for screen in NSScreen.screens {
            let canvas = CGRect(origin: .zero, size: screen.frame.size)
            var rects: [CGRect] = []
            for entry in info {
                guard (entry[kCGWindowLayer as String] as? Int) == 0 else { continue }
                guard let bounds = entry[kCGWindowBounds as String] as? [String: Any],
                      let x = cgFloat(bounds["X"]),
                      let y = cgFloat(bounds["Y"]),
                      let width = cgFloat(bounds["Width"]),
                      let height = cgFloat(bounds["Height"]),
                      width >= 40, height >= 40 else { continue }
                let local = ScreenshotLayout.localFlippedRect(
                    cgBounds: CGRect(x: x, y: y, width: width, height: height),
                    primaryMaxY: primaryMaxY,
                    screenFrame: screen.frame
                ).intersection(canvas)
                if local.width >= 32, local.height >= 32 {
                    rects.append(local)
                }
            }
            result[screen.displayID] = rects
        }
        return result
    }

    private static func cgFloat(_ value: Any?) -> CGFloat? {
        if let number = value as? CGFloat { return number }
        if let number = value as? Double { return CGFloat(number) }
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        return nil
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
