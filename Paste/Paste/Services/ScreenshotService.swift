import AppKit
import Combine
import CoreGraphics
import Foundation
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

    var title: String {
        switch self {
        case .region: return "截取区域"
        case .window: return "截取窗口"
        case .fullScreen: return "截取整屏"
        }
    }

    var systemImage: String {
        switch self {
        case .region: return "viewfinder"
        case .window: return "macwindow"
        case .fullScreen: return "display"
        }
    }

    /// Shown under the preview title in the history.
    var subtitle: String {
        switch self {
        case .region: return "区域截图"
        case .window: return "窗口截图"
        case .fullScreen: return "整屏截图"
        }
    }

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

/// Captures screenshots through the system `screencapture` tool and files the result
/// in clipboard history like any other copied image.
///
/// Shelling out to `screencapture` instead of ScreenCaptureKit keeps the native
/// selection overlay (magnifier, Space to switch to window mode, Esc to cancel) and
/// leaves the pixel grabbing to an Apple-signed binary.
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
        guard !isCapturing else { return }
        isCapturing = true

        // Our own shelf must not end up in the shot; bring it back afterwards so the
        // new screenshot is visible where the user started the capture.
        let restorePanel = StatusItemController.shared.isPanelVisible
        if restorePanel {
            StatusItemController.shared.hidePanel()
        }
        requestScreenRecordingAccessIfNeeded()

        let output = Self.makeOutputURL()
        let arguments = mode.arguments(output: output.path)
        // Give the shelf time to animate away before the pixels are read.
        let delay: TimeInterval = restorePanel ? 0.3 : 0

        // Captured strongly: this is a singleton, and a weak capture cannot be read
        // from the nested task that hands the result back to the main actor.
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            let status = Self.runScreenCapture(arguments)
            let data = Self.readPNG(at: output)
            // OCR stays on this queue and ahead of the pasteboard write: the text has
            // to be there by the time the user reaches for ⌘V.
            let text = data.flatMap { recognizeText ? TextRecognizer.recognize(imageData: $0) : nil }
            Task { @MainActor in
                self.finish(
                    mode: mode,
                    data: data,
                    text: text,
                    recognizeText: recognizeText,
                    status: status,
                    restorePanel: restorePanel
                )
            }
        }
    }

    private func finish(
        mode: ScreenshotMode,
        data: Data?,
        text: String?,
        recognizeText: Bool,
        status: Int32,
        restorePanel: Bool
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
            if restorePanel {
                StatusItemController.shared.showPanel()
            }
            return
        }

        if recognizeText {
            finishTextCapture(mode: mode, text: text, restorePanel: restorePanel)
            return
        }

        guard let payload = Self.payload(mode: mode, pngData: data) else {
            if restorePanel {
                StatusItemController.shared.showPanel()
            }
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
        if restorePanel {
            StatusItemController.shared.showPanel()
        }
        // The strip under the pointer: read the text, save the file, or dismiss.
        // The pointer sits where the selection ended, so the bar hangs just below
        // the screenshot the user just drew.
        ScreenshotActionBar.shared.show(
            thumbnail: thumbnail,
            title: "\(payload.previewTitle) · 已复制",
            anchor: NSEvent.mouseLocation,
            actions: .init(
                recognizeText: { [self] in recognizeLastCapture() },
                save: { [self] in saveLastCapture() }
            )
        )
    }

    /// Reads the text in the capture that just landed, puts it on the pasteboard and
    /// hands it to the store to attach to the image item. The picture stays.
    func recognizeLastCapture() {
        guard let capture = lastCapture else { return }
        queue.async { [self] in
            let text = TextRecognizer.recognize(imageData: capture.pngData)
            Task { @MainActor in
                guard let text, !text.isEmpty else {
                    ScreenshotHUD.shared.show(thumbnail: capture.thumbnail, title: capture.title, detail: "未识别到文字")
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

    /// Writes the capture to 下载 as a PNG. Sandboxed builds cannot reach the folder
    /// directly, so they fall back to a save panel pointed there.
    func saveLastCapture() {
        guard let capture = lastCapture else { return }
        Self.saveImage(capture.pngData, suggestedName: Self.downloadFileName(), thumbnail: capture.thumbnail)
    }

    static func downloadFileName(now: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "PasteNest 截图 \(formatter.string(from: now)).png"
    }

    /// Shared by the action bar and the history cards' 保存图片 action.
    static func saveImage(_ pngData: Data, suggestedName: String, thumbnail: NSImage? = nil) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        if let downloads {
            let target = uniqueURL(in: downloads, name: suggestedName)
            if (try? pngData.write(to: target, options: .atomic)) != nil {
                ScreenshotHUD.shared.show(thumbnail: thumbnail, title: target.lastPathComponent, detail: "已保存到「下载」")
                return
            }
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName
        panel.directoryURL = downloads
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if (try? pngData.write(to: url, options: .atomic)) != nil {
            ScreenshotHUD.shared.show(thumbnail: thumbnail, title: url.lastPathComponent, detail: "已保存")
        }
    }

    /// "name.png", then "name 2.png", … so a burst of saves never overwrites.
    static func uniqueURL(in directory: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter)").appendingPathExtension(ext)
            counter += 1
        }
        return candidate
    }

    /// A 识字 capture keeps only the words: the image is discarded, the text goes to
    /// the pasteboard and into history as a normal text item.
    private func finishTextCapture(mode: ScreenshotMode, text: String?, restorePanel: Bool) {
        guard let text, !text.isEmpty else {
            if restorePanel {
                StatusItemController.shared.showPanel()
            } else {
                ScreenshotHUD.shared.show(thumbnail: nil, title: "截图识字", detail: "未识别到文字")
            }
            return
        }
        ClipboardMonitor.shared.ignoreNextPasteboardChange()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let payload = Self.textPayload(mode: mode, text: text)
        onCaptured?(payload)
        if restorePanel {
            StatusItemController.shared.showPanel()
        } else {
            ScreenshotHUD.shared.show(
                thumbnail: nil,
                title: "截图识字",
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
        guard let text else { return "未识别到文字" }
        return "已识别 \(TextRecognizer.characterCount(of: text)) 字，文字已复制"
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
        alert.messageText = "需要「屏幕录制」权限"
        alert.informativeText = "macOS 要求截图前先授权。请在「系统设置 → 隐私与安全性 → 屏幕录制」中勾选 PasteNest，然后重新启动 PasteNest。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Self.openScreenRecordingSettings()
        }
    }

    private func presentFailureAlert(status: Int32) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "截图失败"
        alert.informativeText = "系统截图工具返回错误代码 \(status)。请重试，或用系统快捷键 ⇧⌘4 截图后由 PasteNest 自动收录。"
        alert.addButton(withTitle: "好")
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
            sourceAppName: "截图",
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
            previewSubtitle: "截图识字 · \(TextRecognizer.characterCount(of: text)) 字",
            colorHex: nil,
            sourceAppName: "截图识字",
            sourceAppBundleID: nil
        )
    }

    /// Searchable on its own: typing 截图 finds every capture.
    static func previewTitle(width: Int, height: Int) -> String {
        "截图 \(width)×\(height)"
    }

    /// `NSImage.size` is in points; the bitmap rep carries the Retina pixel count.
    private static func pixelSize(of image: NSImage) -> (width: Int, height: Int) {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        return (Int(image.size.width), Int(image.size.height))
    }
}
