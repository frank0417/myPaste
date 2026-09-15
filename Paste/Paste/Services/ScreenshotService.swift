import AppKit
import Combine
import CoreGraphics
import Foundation

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
    /// Set by `AppDelegate`; only used to read the text-recognition preference.
    weak var appState: AppState?

    @Published private(set) var isCapturing = false

    private let queue = DispatchQueue(label: "com.mypaste.ClipStack.screenshot")

    private init() {}

    func capture(_ mode: ScreenshotMode) {
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
        let recognizeText = appState?.screenshotTextRecognition ?? true

        // Captured strongly: this is a singleton, and a weak capture cannot be read
        // from the nested task that hands the result back to the main actor.
        queue.asyncAfter(deadline: .now() + delay) { [self] in
            let status = Self.runScreenCapture(arguments)
            let data = Self.readPNG(at: output)
            // OCR stays on this queue and ahead of the pasteboard write: the text has
            // to be there by the time the user reaches for ⌘V.
            let text = data.flatMap { recognizeText ? TextRecognizer.recognize(imageData: $0) : nil }
            Task { @MainActor in
                self.finish(mode: mode, data: data, text: text, status: status, restorePanel: restorePanel)
            }
        }
    }

    private func finish(
        mode: ScreenshotMode,
        data: Data?,
        text: String?,
        status: Int32,
        restorePanel: Bool
    ) {
        isCapturing = false

        guard let data, let payload = Self.payload(mode: mode, pngData: data, text: text) else {
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

        writeToPasteboard(data, text: text)
        onCaptured?(payload)
        if restorePanel {
            StatusItemController.shared.showPanel()
        } else {
            // Nothing else on screen would confirm the capture, so say what happened.
            ScreenshotHUD.shared.show(
                thumbnail: payload.thumbnailData.flatMap(NSImage.init(data:)),
                title: payload.previewTitle,
                detail: Self.hudDetail(text: text, recognitionEnabled: appState?.screenshotTextRecognition ?? true)
            )
        }
    }

    /// Screenshots go on the pasteboard too, so ⌘V works right after capturing.
    /// Image and recognized text ride along as two representations of one item, so
    /// a text field pastes the text while an image view pastes the picture.
    private func writeToPasteboard(_ pngData: Data, text: String?) {
        guard let item = ClipboardMonitor.imagePasteboardItem(imageData: pngData, text: text) else { return }
        ClipboardMonitor.shared.ignoreNextPasteboardChange()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    static func hudDetail(text: String?, recognitionEnabled: Bool) -> String {
        guard recognitionEnabled else { return "图片已复制" }
        guard let text else { return "图片已复制 · 未识别到文字" }
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

    /// Prompts once so ClipStack shows up in 隐私与安全性 → 屏幕录制.
    private func requestScreenRecordingAccessIfNeeded() {
        guard !Self.hasScreenRecordingAccess else { return }
        _ = CGRequestScreenCaptureAccess()
    }

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要「屏幕录制」权限"
        alert.informativeText = "macOS 要求截图前先授权。请在「系统设置 → 隐私与安全性 → 屏幕录制」中勾选 ClipStack，然后重新启动 ClipStack。"
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
        alert.informativeText = "系统截图工具返回错误代码 \(status)。请重试，或用系统快捷键 ⇧⌘4 截图后由 ClipStack 自动收录。"
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
            .appendingPathComponent("ClipStack-Screenshot-\(UUID().uuidString)")
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

    static func payload(mode: ScreenshotMode, pngData: Data, text: String?) -> CapturedClipboardPayload? {
        guard let image = NSImage(data: pngData) else { return nil }
        let size = pixelSize(of: image)
        return CapturedClipboardPayload(
            contentType: .image,
            // Recognized text rides on the image item, which makes the capture
            // findable by its own content through the existing hybrid search.
            plainText: text,
            imageData: pngData,
            richTextData: nil,
            fileURLs: [],
            contentHash: ClipboardMonitor.hashData(pngData),
            previewTitle: previewTitle(width: size.width, height: size.height),
            previewSubtitle: subtitle(mode: mode, text: text),
            colorHex: nil,
            sourceAppName: "截图",
            sourceAppBundleID: nil,
            thumbnailData: ClipboardMonitor.thumbnailData(from: image, maxSize: 240)
        )
    }

    /// Searchable on its own: typing 截图 finds every capture.
    static func previewTitle(width: Int, height: Int) -> String {
        "截图 \(width)×\(height)"
    }

    static func subtitle(mode: ScreenshotMode, text: String?) -> String {
        guard let text else { return mode.subtitle }
        return "\(mode.subtitle) · 识别 \(TextRecognizer.characterCount(of: text)) 字"
    }

    /// `NSImage.size` is in points; the bitmap rep carries the Retina pixel count.
    private static func pixelSize(of image: NSImage) -> (width: Int, height: Int) {
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        return (Int(image.size.width), Int(image.size.height))
    }
}
