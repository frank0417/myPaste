import AppKit
import CoreText
import Foundation

/// Drawing tools on the capture overlay. `move` is the implicit pointer: drag the
/// selection, then pick a tool to annotate inside it.
enum ScreenshotTool: String, CaseIterable, Identifiable {
    case move
    case rect
    case ellipse
    case line
    case arrow
    case pen
    case text
    case pin
    case mosaic
    case crop

    var id: String { rawValue }

    var title: String { ScreenshotL10n.toolTitle(self) }

    var systemImage: String {
        switch self {
        case .move: return "arrow.up.left.and.arrow.down.right"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "line.diagonal.arrow"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .pin: return "number"
        case .mosaic: return "square.grid.3x3"
        case .crop: return "crop"
        }
    }

    /// Tools shown as icon buttons on the annotation strip.
    static let toolbarTools: [ScreenshotTool] = [
        .rect, .ellipse, .line, .arrow, .pen, .text, .pin, .mosaic, .crop
    ]

    var isDrawable: Bool {
        switch self {
        case .move, .crop: return false
        default: return true
        }
    }

    /// Click-once tools: they stamp on mouse-down and never drag a shape.
    var isStamp: Bool {
        self == .text || self == .pin
    }
}

/// Hover captions for chrome on the annotation strip (not drawing tools).
enum ScreenshotToolbarHintText {
    static var drag: String { ScreenshotL10n.string(.drag) }
    static var color: String { ScreenshotL10n.string(.color) }
    static var width: String { ScreenshotL10n.string(.width) }
    static var undo: String { ScreenshotL10n.string(.undo) }
    static var download: String { ScreenshotL10n.string(.download) }
    static var recognizeText: String { ScreenshotL10n.string(.recognizeText) }
    static var cancel: String { ScreenshotL10n.string(.cancel) }
    static var confirm: String { ScreenshotL10n.string(.confirm) }
}

/// Languages the screenshot overlay localizes into. Matches Xcode `knownRegions`
/// (`zh-Hans`, `en`) plus Traditional Chinese, which screen OCR already requests.
enum ScreenshotLanguage: String, CaseIterable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"

    /// App development region — used when no preferred language is supported.
    static let fallback = ScreenshotLanguage.simplifiedChinese

    static func resolve(preferredLanguages: [String] = Locale.preferredLanguages) -> ScreenshotLanguage {
        for raw in preferredLanguages {
            let tag = raw.replacingOccurrences(of: "_", with: "-")
            if let match = match(tag) { return match }
        }
        return fallback
    }

    fileprivate static func match(_ tag: String) -> ScreenshotLanguage? {
        let parts = tag.split(separator: "-").map { $0.lowercased() }
        guard let first = parts.first else { return nil }
        if first == "zh" {
            let rest = parts.dropFirst().joined(separator: "-")
            if rest.hasPrefix("hant") || rest.hasPrefix("tw") || rest.hasPrefix("hk") || rest.hasPrefix("mo") {
                return .traditionalChinese
            }
            return .simplifiedChinese
        }
        if first == "en" { return .english }
        return nil
    }
}

enum ScreenshotL10n {
    enum Key: String, CaseIterable {
        case move, rect, ellipse, line, arrow, pen, text, pin, mosaic, crop
        case drag, color, width, undo, download, cancel, confirm
        case textPlaceholder
        case recognizeText, close, copy, ocrEmpty, ocrWorking, ocrDismiss
        case modeRegion, modeWindow, modeFullScreen
        case subtitleRegion, subtitleWindow, subtitleFullScreen
        case imageCopied, copiedSuffix, savedToDownloads, saved
        case textCapture, sourceScreenshot
        case permissionTitle, permissionBody, openSystemSettings, later
        case captureFailed, captureFailedBody, captureFailedBodyCode, ok
    }

    static func string(_ key: Key, language: ScreenshotLanguage = .resolve()) -> String {
        strings[language]?[key] ?? strings[ScreenshotLanguage.fallback]![key]!
    }

    static func toolTitle(_ tool: ScreenshotTool, language: ScreenshotLanguage = .resolve()) -> String {
        switch tool {
        case .move: return string(.move, language: language)
        case .rect: return string(.rect, language: language)
        case .ellipse: return string(.ellipse, language: language)
        case .line: return string(.line, language: language)
        case .arrow: return string(.arrow, language: language)
        case .pen: return string(.pen, language: language)
        case .text: return string(.text, language: language)
        case .pin: return string(.pin, language: language)
        case .mosaic: return string(.mosaic, language: language)
        case .crop: return string(.crop, language: language)
        }
    }

    static func modeTitle(_ mode: ScreenshotMode, language: ScreenshotLanguage = .resolve()) -> String {
        switch mode {
        case .region: return string(.modeRegion, language: language)
        case .window: return string(.modeWindow, language: language)
        case .fullScreen: return string(.modeFullScreen, language: language)
        }
    }

    static func modeSubtitle(_ mode: ScreenshotMode, language: ScreenshotLanguage = .resolve()) -> String {
        switch mode {
        case .region: return string(.subtitleRegion, language: language)
        case .window: return string(.subtitleWindow, language: language)
        case .fullScreen: return string(.subtitleFullScreen, language: language)
        }
    }

    static func previewTitle(width: Int, height: Int, language: ScreenshotLanguage = .resolve()) -> String {
        switch language {
        case .simplifiedChinese: return "截图 \(width)×\(height)"
        case .traditionalChinese: return "截圖 \(width)×\(height)"
        case .english: return "Screenshot \(width)×\(height)"
        }
    }

    static func downloadFileName(stamp: String, language: ScreenshotLanguage = .resolve()) -> String {
        switch language {
        case .simplifiedChinese: return "PasteNest 截图 \(stamp).png"
        case .traditionalChinese: return "PasteNest 截圖 \(stamp).png"
        case .english: return "PasteNest Screenshot \(stamp).png"
        }
    }

    static func copiedTitle(_ title: String, language: ScreenshotLanguage = .resolve()) -> String {
        "\(title) · \(string(.copiedSuffix, language: language))"
    }

    static func hudRecognizedCopied(_ count: Int, language: ScreenshotLanguage = .resolve()) -> String {
        switch language {
        case .simplifiedChinese: return "已识别 \(count) 字，文字已复制"
        case .traditionalChinese: return "已辨識 \(count) 字，文字已複製"
        case .english: return count == 1 ? "Recognized 1 character, copied" : "Recognized \(count) characters, copied"
        }
    }

    static func hudRecognizedMenu(_ count: Int, language: ScreenshotLanguage = .resolve()) -> String {
        switch language {
        case .simplifiedChinese: return "已识别 \(count) 字，右键可复制文字"
        case .traditionalChinese: return "已辨識 \(count) 字，按右鍵可複製文字"
        case .english: return count == 1 ? "Recognized 1 character; right-click to copy" : "Recognized \(count) characters; right-click to copy"
        }
    }

    static func ocrAttached(_ count: Int, language: ScreenshotLanguage = .resolve()) -> String {
        switch language {
        case .simplifiedChinese: return "已识字 \(count) 字"
        case .traditionalChinese: return "已識字 \(count) 字"
        case .english: return count == 1 ? "OCR 1 char" : "OCR \(count) chars"
        }
    }

    static func textCaptureSubtitle(_ count: Int, language: ScreenshotLanguage = .resolve()) -> String {
        "\(string(.textCapture, language: language)) · \(ocrAttached(count, language: language))"
    }

    static func captureFailedBody(status: Int32, language: ScreenshotLanguage = .resolve()) -> String {
        if status == 0 {
            return string(.captureFailedBody, language: language)
        }
        switch language {
        case .simplifiedChinese:
            return "无法读取屏幕画面（错误 \(status)）。请确认已允许「屏幕录制」权限后重试，或用系统快捷键 ⇧⌘4 截图后由 PasteNest 自动收录。"
        case .traditionalChinese:
            return "無法讀取螢幕畫面（錯誤 \(status)）。請確認已允許「螢幕錄製」權限後重試，或用系統快捷鍵 ⇧⌘4 截圖後由 PasteNest 自動收錄。"
        case .english:
            return "Could not read the screen (error \(status)). Grant Screen Recording access and try again, or capture with ⇧⌘4 and PasteNest will file it."
        }
    }

    /// Drops a previously attached OCR suffix, in any of the three languages.
    static func stripOCRSuffix(_ subtitle: String?) -> String? {
        guard let subtitle else { return nil }
        let markers = [" · 已识字", " · 已識字", " · OCR "]
        for marker in markers {
            if let range = subtitle.range(of: marker) {
                return String(subtitle[..<range.lowerBound])
            }
        }
        return subtitle
    }

    private static let strings: [ScreenshotLanguage: [Key: String]] = [
        .simplifiedChinese: [
            .move: "调整选区",
            .rect: "矩形",
            .ellipse: "圆形",
            .line: "直线",
            .arrow: "箭头",
            .pen: "画笔",
            .text: "文字",
            .pin: "序号",
            .mosaic: "马赛克",
            .crop: "重新选区",
            .drag: "拖动工具条",
            .color: "颜色",
            .width: "粗细",
            .undo: "撤销",
            .download: "下载截图",
            .cancel: "取消（Esc）",
            .confirm: "完成（Enter）",
            .textPlaceholder: "输入文字",
            .recognizeText: "识别文字",
            .close: "关闭",
            .copy: "复制",
            .ocrEmpty: "未识别到文字",
            .ocrWorking: "正在识别…",
            .ocrDismiss: "取消",
            .modeRegion: "截取区域",
            .modeWindow: "截取窗口",
            .modeFullScreen: "截取整屏",
            .subtitleRegion: "区域截图",
            .subtitleWindow: "窗口截图",
            .subtitleFullScreen: "整屏截图",
            .imageCopied: "图片已复制",
            .copiedSuffix: "已复制",
            .savedToDownloads: "已保存到「下载」",
            .saved: "已保存",
            .textCapture: "截图识字",
            .sourceScreenshot: "截图",
            .permissionTitle: "需要「屏幕录制」权限",
            .permissionBody: "macOS 要求截图前先授权。请在「系统设置 → 隐私与安全性 → 屏幕录制」中勾选 PasteNest，然后重新启动 PasteNest。",
            .openSystemSettings: "打开系统设置",
            .later: "稍后",
            .captureFailed: "截图失败",
            .captureFailedBody: "无法读取屏幕画面。请确认已允许「屏幕录制」权限后重试，或用系统快捷键 ⇧⌘4 截图后由 PasteNest 自动收录。",
            .captureFailedBodyCode: "无法读取屏幕画面。请确认已允许「屏幕录制」权限后重试，或用系统快捷键 ⇧⌘4 截图后由 PasteNest 自动收录。",
            .ok: "好"
        ],
        .traditionalChinese: [
            .move: "調整選區",
            .rect: "矩形",
            .ellipse: "圓形",
            .line: "直線",
            .arrow: "箭頭",
            .pen: "畫筆",
            .text: "文字",
            .pin: "序號",
            .mosaic: "馬賽克",
            .crop: "重新選區",
            .drag: "拖曳工具列",
            .color: "顏色",
            .width: "粗細",
            .undo: "復原",
            .download: "下載截圖",
            .cancel: "取消（Esc）",
            .confirm: "完成（Enter）",
            .textPlaceholder: "輸入文字",
            .recognizeText: "辨識文字",
            .close: "關閉",
            .copy: "複製",
            .ocrEmpty: "未辨識到文字",
            .ocrWorking: "正在辨識…",
            .ocrDismiss: "取消",
            .modeRegion: "截取區域",
            .modeWindow: "截取視窗",
            .modeFullScreen: "截取整屏",
            .subtitleRegion: "區域截圖",
            .subtitleWindow: "視窗截圖",
            .subtitleFullScreen: "整屏截圖",
            .imageCopied: "圖片已複製",
            .copiedSuffix: "已複製",
            .savedToDownloads: "已儲存到「下載」",
            .saved: "已儲存",
            .textCapture: "截圖識字",
            .sourceScreenshot: "截圖",
            .permissionTitle: "需要「螢幕錄製」權限",
            .permissionBody: "macOS 要求截圖前先授權。請在「系統設定 → 隱私權與安全性 → 螢幕錄製」中勾選 PasteNest，然後重新啟動 PasteNest。",
            .openSystemSettings: "打開系統設定",
            .later: "稍後",
            .captureFailed: "截圖失敗",
            .captureFailedBody: "無法讀取螢幕畫面。請確認已允許「螢幕錄製」權限後重試，或用系統快捷鍵 ⇧⌘4 截圖後由 PasteNest 自動收錄。",
            .captureFailedBodyCode: "無法讀取螢幕畫面。請確認已允許「螢幕錄製」權限後重試，或用系統快捷鍵 ⇧⌘4 截圖後由 PasteNest 自動收錄。",
            .ok: "好"
        ],
        .english: [
            .move: "Adjust selection",
            .rect: "Rectangle",
            .ellipse: "Ellipse",
            .line: "Line",
            .arrow: "Arrow",
            .pen: "Pen",
            .text: "Text",
            .pin: "Number",
            .mosaic: "Mosaic",
            .crop: "Reselect",
            .drag: "Move toolbar",
            .color: "Color",
            .width: "Thickness",
            .undo: "Undo",
            .download: "Save screenshot",
            .cancel: "Cancel (Esc)",
            .confirm: "Done (Enter)",
            .textPlaceholder: "Type text",
            .recognizeText: "Recognize text",
            .close: "Close",
            .copy: "Copy",
            .ocrEmpty: "No text found",
            .ocrWorking: "Recognizing…",
            .ocrDismiss: "Cancel",
            .modeRegion: "Capture region",
            .modeWindow: "Capture window",
            .modeFullScreen: "Capture full screen",
            .subtitleRegion: "Region screenshot",
            .subtitleWindow: "Window screenshot",
            .subtitleFullScreen: "Full-screen screenshot",
            .imageCopied: "Image copied",
            .copiedSuffix: "Copied",
            .savedToDownloads: "Saved to Downloads",
            .saved: "Saved",
            .textCapture: "Screenshot OCR",
            .sourceScreenshot: "Screenshot",
            .permissionTitle: "Screen Recording access needed",
            .permissionBody: "macOS requires permission before capturing. Enable PasteNest in System Settings → Privacy & Security → Screen Recording, then restart PasteNest.",
            .openSystemSettings: "Open System Settings",
            .later: "Later",
            .captureFailed: "Screenshot failed",
            .captureFailedBody: "Could not read the screen. Grant Screen Recording access and try again, or capture with ⇧⌘4 and PasteNest will file it.",
            .captureFailedBodyCode: "Could not read the screen. Grant Screen Recording access and try again, or capture with ⇧⌘4 and PasteNest will file it.",
            .ok: "OK"
        ]
    ]
}

enum ScreenshotHandle: String, CaseIterable {
    case nw, n, ne, e, se, s, sw, w, move
}

/// One mark on the frozen screenshot. Coordinates are in the canvas's top-left
/// point space (the same space the overlay view uses).
struct ScreenshotStroke: Equatable {
    var id: UUID
    var tool: ScreenshotTool
    var colorHex: String
    var lineWidth: CGFloat
    var points: [CGPoint]
    var text: String
    var pinNumber: Int

    init(
        id: UUID = UUID(),
        tool: ScreenshotTool,
        colorHex: String,
        lineWidth: CGFloat,
        points: [CGPoint],
        text: String = "",
        pinNumber: Int = 0
    ) {
        self.id = id
        self.tool = tool
        self.colorHex = colorHex
        self.lineWidth = lineWidth
        self.points = points
        self.text = text
        self.pinNumber = pinNumber
    }

    var start: CGPoint { points.first ?? .zero }
    var end: CGPoint { points.last ?? start }

    var bounds: CGRect {
        switch tool {
        case .pen:
            return ScreenshotLayout.bounds(of: points, padding: lineWidth)
        case .text:
            let width = max(40, CGFloat(text.count) * (16 + lineWidth) * 0.62)
            let height = 16 + lineWidth + 6
            return CGRect(x: start.x, y: start.y, width: width, height: height)
        case .pin:
            let size: CGFloat = 22
            return CGRect(x: start.x - size / 2, y: start.y - size / 2, width: size, height: size)
        default:
            return ScreenshotLayout.normalizedRect(start, end)
        }
    }
}

/// Pure geometry for the overlay: selection handles, toolbar placement, snapping.
/// Mirrored by `Paste/PasteTests/screenshot_editor.test.mjs`.
enum ScreenshotLayout {
    static let handleRadius: CGFloat = 4
    static let handleHitRadius: CGFloat = 10
    static let minSelection: CGFloat = 4
    static let toolbarSize = CGSize(width: 672, height: 48)
    /// Extra host height above the capsule so icon hover hints are not clipped.
    static let toolbarHintHeight: CGFloat = 28
    static let toolbarGap: CGFloat = 12
    /// Accessory / first-click activation must not eat the opening drag.
    static let overlayAcceptsFirstMouse = true
    /// Annotation-strip buttons use `NSCursor.pointingHand` on hover.
    static let toolbarButtonCursorIsPointingHand = true
    /// The whole strip can be dragged, not only the ellipsis grip.
    static let toolbarIsFullyDraggable = true
    /// Plain captures keep 识别文字 on the annotation strip.
    static let annotationToolbarIncludesOCR = true
    /// Result card hangs to the right of the crop; flips left when it would clip.
    static let ocrPanelSize = CGSize(width: 280, height: 240)
    static let ocrPanelMinHeight: CGFloat = 140
    static let ocrPanelMaxHeight: CGFloat = 420
    static let ocrPanelGap: CGFloat = 12
    /// The card is painted white; force aqua so recognized text is not white-on-white
    /// when the freeze window itself is dark.
    static let ocrPanelUsesLightAppearance = true
    /// Explicit dark ink on the white card. `labelColor` follows the overlay window
    /// and disappears against the card when the freeze is dark.
    static let ocrPanelTextColorHex = "#222426"
    /// The freeze canvas is flipped. `NSTextView` inside that hierarchy draws blank,
    /// so the result is a SwiftUI `Text` like the card title (which already shows).
    static let ocrResultUsesSwiftUIText = true
    /// Copying recognized text is the job; dismiss the freeze instead of leaving
    /// the user to hit Esc. Must not confirm: that would replace the text with a PNG.
    static let ocrCopyDismissesOverlay = true
    static let sizeBadgeHeight: CGFloat = 22
    static let sizeBadgeGap: CGFloat = 6
    static let mosaicBlock: CGFloat = 10
    static let arrowHeadLength: CGFloat = 14
    static let arrowHeadAngle: CGFloat = .pi / 6
    /// Overlay canvas is flipped (origin top-left). The freeze is blitted as a
    /// native-pixel CGImage with a Y flip so it stays upright and sharp.
    static let imageDrawRespectsFlipped = true
    /// Composite paints the CGImage before flipping the context for strokes.
    static let compositeDrawsImageBeforeFlip = true

    /// ScreenCaptureKit output size in pixels. `SCStreamConfiguration` defaults to
    /// 1920×1080, which looks soft on a Retina display; always size the buffer from
    /// the filter's point scale, and never smaller than `backingScaleFactor`.
    static func outputPixelSize(
        contentRect: CGSize,
        pointPixelScale: CGFloat,
        screenPoints: CGSize,
        backingScale: CGFloat
    ) -> (width: Int, height: Int) {
        let filterScale = pointPixelScale > 0 ? pointPixelScale : 1
        let filterWidth = Int((contentRect.width * filterScale).rounded())
        let filterHeight = Int((contentRect.height * filterScale).rounded())
        let screenWidth = Int((screenPoints.width * max(backingScale, 1)).rounded())
        let screenHeight = Int((screenPoints.height * max(backingScale, 1)).rounded())
        if filterWidth >= screenWidth && filterHeight >= screenHeight {
            return (max(filterWidth, 1), max(filterHeight, 1))
        }
        return (max(screenWidth, 1), max(screenHeight, 1))
    }
    static let defaultColorHex = "#F5222D"
    static let selectionColorHex = "#2F80FF"
    static let dimOpacity: CGFloat = 0.55
    static let palette = [
        "#F5222D", "#FA8C16", "#FADB14", "#52C41A",
        "#1890FF", "#722ED1", "#FFFFFF", "#1B2A2F"
    ]
    static let lineWidths: [CGFloat] = [2, 3, 5]

    static func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var r = rect
        if r.width > bounds.width { r.size.width = bounds.width }
        if r.height > bounds.height { r.size.height = bounds.height }
        r.origin.x = min(max(r.origin.x, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.origin.y, bounds.minY), bounds.maxY - r.height)
        return r
    }

    static func sizeLabel(width: CGFloat, height: CGFloat) -> String {
        "\(Int(width.rounded())) × \(Int(height.rounded()))"
    }

    static func handlePoints(in rect: CGRect) -> [ScreenshotHandle: CGPoint] {
        let midX = rect.midX
        let midY = rect.midY
        return [
            .nw: CGPoint(x: rect.minX, y: rect.minY),
            .n: CGPoint(x: midX, y: rect.minY),
            .ne: CGPoint(x: rect.maxX, y: rect.minY),
            .e: CGPoint(x: rect.maxX, y: midY),
            .se: CGPoint(x: rect.maxX, y: rect.maxY),
            .s: CGPoint(x: midX, y: rect.maxY),
            .sw: CGPoint(x: rect.minX, y: rect.maxY),
            .w: CGPoint(x: rect.minX, y: midY)
        ]
    }

    /// Handle under `point`, then `.move` when inside the selection, otherwise nil.
    static func hitTest(_ point: CGPoint, selection: CGRect) -> ScreenshotHandle? {
        let points = handlePoints(in: selection)
        let order: [ScreenshotHandle] = [.nw, .ne, .se, .sw, .n, .e, .s, .w]
        for handle in order {
            if let origin = points[handle], hypot(point.x - origin.x, point.y - origin.y) <= handleHitRadius {
                return handle
            }
        }
        if selection.insetBy(dx: -2, dy: -2).contains(point) {
            return .move
        }
        return nil
    }

    static func resize(_ rect: CGRect, handle: ScreenshotHandle, to point: CGPoint, bounds: CGRect) -> CGRect {
        var minX = rect.minX
        var minY = rect.minY
        var maxX = rect.maxX
        var maxY = rect.maxY
        switch handle {
        case .n, .ne, .nw: minY = point.y
        case .s, .se, .sw: maxY = point.y
        default: break
        }
        switch handle {
        case .e, .ne, .se: maxX = point.x
        case .w, .nw, .sw: minX = point.x
        case .move, .n, .s: break
        }
        let result = CGRect(
            x: min(minX, maxX),
            y: min(minY, maxY),
            width: abs(maxX - minX),
            height: abs(maxY - minY)
        )
        return clamp(result, to: bounds)
    }

    static func move(_ rect: CGRect, by delta: CGSize, bounds: CGRect) -> CGRect {
        clamp(rect.offsetBy(dx: delta.width, dy: delta.height), to: bounds)
    }

    /// Shift locks a rect/ellipse to a square, or a line/arrow to 45° increments.
    static func snapEnd(from: CGPoint, to: CGPoint, tool: ScreenshotTool, shift: Bool) -> CGPoint {
        guard shift else { return to }
        switch tool {
        case .rect, .ellipse, .mosaic:
            let dx = to.x - from.x
            let dy = to.y - from.y
            let side = min(abs(dx), abs(dy))
            return CGPoint(
                x: from.x + (dx < 0 ? -side : side),
                y: from.y + (dy < 0 ? -side : side)
            )
        case .line, .arrow:
            let dx = to.x - from.x
            let dy = to.y - from.y
            let length = hypot(dx, dy)
            let snapped = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            return CGPoint(x: from.x + cos(snapped) * length, y: from.y + sin(snapped) * length)
        default:
            return to
        }
    }

    /// Hang below the selection, flip above when there is no room, then clamp.
    /// The returned rect is the hosting view: capsule plus hint space above it.
    static func toolbarFrame(
        selection: CGRect,
        canvas: CGRect,
        size: CGSize = toolbarSize,
        offset: CGSize = .zero
    ) -> CGRect {
        let host = CGSize(width: size.width, height: size.height + toolbarHintHeight)
        var x = selection.midX - host.width / 2 + offset.width
        var capsuleY = selection.maxY + toolbarGap + offset.height
        if capsuleY + size.height > canvas.maxY - 8 {
            capsuleY = selection.minY - size.height - toolbarGap + offset.height
        }
        var y = capsuleY - toolbarHintHeight
        x = min(max(x, canvas.minX + 8), max(canvas.minX + 8, canvas.maxX - host.width - 8))
        y = min(max(y, canvas.minY + 8), max(canvas.minY + 8, canvas.maxY - host.height - 8))
        return CGRect(x: x, y: y, width: host.width, height: host.height)
    }

    static func ocrPanelHeight(for selection: CGRect, canvas: CGRect) -> CGFloat {
        let height = min(max(selection.height, ocrPanelMinHeight), ocrPanelMaxHeight)
        return min(height, max(ocrPanelMinHeight, canvas.height - 16))
    }

    /// Sit to the right of the selection, flip to the left when there is no room,
    /// then clamp. Height follows the crop, within min/max.
    static func ocrPanelFrame(
        selection: CGRect,
        canvas: CGRect,
        size: CGSize = ocrPanelSize
    ) -> CGRect {
        let width = size.width
        let height = size.height
        var x = selection.maxX + ocrPanelGap
        if x + width > canvas.maxX - 8 {
            x = selection.minX - width - ocrPanelGap
        }
        x = min(max(x, canvas.minX + 8), max(canvas.minX + 8, canvas.maxX - width - 8))
        var y = selection.minY
        if y + height > canvas.maxY - 8 {
            y = canvas.maxY - height - 8
        }
        y = min(max(y, canvas.minY + 8), max(canvas.minY + 8, canvas.maxY - height - 8))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Dark size pill, sitting just above the top-left of the selection.
    static func sizeBadgeFrame(
        selection: CGRect,
        canvas: CGRect,
        textWidth: CGFloat
    ) -> CGRect {
        let width = max(52, textWidth + 16)
        let height = sizeBadgeHeight
        var x = selection.minX
        var y = selection.minY - height - sizeBadgeGap
        if y < canvas.minY + 4 {
            y = min(selection.minY + sizeBadgeGap, canvas.maxY - height - 4)
        }
        x = min(max(x, canvas.minX + 4), max(canvas.minX + 4, canvas.maxX - width - 4))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func arrowHead(from: CGPoint, to: CGPoint) -> (CGPoint, CGPoint) {
        let angle = atan2(to.y - from.y, to.x - from.x)
        let left = CGPoint(
            x: to.x - arrowHeadLength * cos(angle - arrowHeadAngle),
            y: to.y - arrowHeadLength * sin(angle - arrowHeadAngle)
        )
        let right = CGPoint(
            x: to.x - arrowHeadLength * cos(angle + arrowHeadAngle),
            y: to.y - arrowHeadLength * sin(angle + arrowHeadAngle)
        )
        return (left, right)
    }

    static func bounds(of points: [CGPoint], padding: CGFloat) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(
            x: minX - padding,
            y: minY - padding,
            width: max(1, maxX - minX + padding * 2),
            height: max(1, maxY - minY + padding * 2)
        )
    }

    /// Smallest on-screen window that contains the point — nested windows pick the
    /// inner one, matching the system window picker.
    static func window(at point: CGPoint, windows: [CGRect]) -> CGRect? {
        windows
            .filter { $0.contains(point) }
            .sorted { $0.width * $0.height < $1.width * $1.height }
            .first
    }

    /// Top-left CG window bounds → SwiftUI/canvas coordinates for one screen.
    static func localFlippedRect(
        cgBounds: CGRect,
        primaryMaxY: CGFloat,
        screenFrame: CGRect
    ) -> CGRect {
        let cocoa = CGRect(
            x: cgBounds.minX,
            y: primaryMaxY - cgBounds.minY - cgBounds.height,
            width: cgBounds.width,
            height: cgBounds.height
        )
        let local = CGRect(
            x: cocoa.minX - screenFrame.minX,
            y: cocoa.minY - screenFrame.minY,
            width: cocoa.width,
            height: cocoa.height
        )
        return CGRect(
            x: local.minX,
            y: screenFrame.height - local.maxY,
            width: local.width,
            height: local.height
        )
    }

    /// Crop rectangle in bitmap pixels. Canvas y is top-left, matching CGImage.
    static func pixelCrop(
        _ selection: CGRect,
        scale: CGFloat,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect {
        let rect = CGRect(
            x: (selection.minX * scale).rounded(),
            y: (selection.minY * scale).rounded(),
            width: max(1, (selection.width * scale).rounded()),
            height: max(1, (selection.height * scale).rounded())
        )
        return rect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
    }
}

/// Composites the crop plus annotations into a PNG.
enum ScreenshotRenderer {
    static func png(
        image: NSImage,
        selection: CGRect,
        strokes: [ScreenshotStroke]
    ) -> Data? {
        guard let source = cgImage(from: image) else { return nil }
        return png(cgImage: source, pointSize: image.size, selection: selection, strokes: strokes)
    }

    static func png(
        cgImage: CGImage,
        pointSize: CGSize,
        selection: CGRect,
        strokes: [ScreenshotStroke]
    ) -> Data? {
        let source = cgImage
        let scale = CGFloat(source.width) / max(pointSize.width, 1)
        let crop = ScreenshotLayout.pixelCrop(
            selection,
            scale: scale,
            imageWidth: source.width,
            imageHeight: source.height
        )
        guard crop.width >= 1, crop.height >= 1, let cropped = source.cropping(to: crop) else {
            return nil
        }

        let width = Int(crop.width)
        let height = Int(crop.height)
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .high
        // Draw the bitmap in default y-up space so the PNG is right-side up, then
        // flip so strokes can use the overlay's top-left coordinates.
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        for stroke in strokes {
            draw(stroke, in: ctx, selection: selection, scale: scale, source: cropped)
        }

        guard let result = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: result)
        return rep.representation(using: .png, properties: [:])
    }

    static func cgImage(from image: NSImage) -> CGImage? {
        let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
        if let best = bitmaps.max(by: { $0.pixelsWide < $1.pixelsWide }), let cgImage = best.cgImage {
            return cgImage
        }
        var proposed = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }

    private static func draw(
        _ stroke: ScreenshotStroke,
        in ctx: CGContext,
        selection: CGRect,
        scale: CGFloat,
        source: CGImage
    ) {
        func px(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: (point.x - selection.minX) * scale,
                y: (point.y - selection.minY) * scale
            )
        }
        let color = NSColor(hex: stroke.colorHex)?.cgColor ?? NSColor.systemRed.cgColor
        let width = max(1, stroke.lineWidth * scale)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch stroke.tool {
        case .rect, .mosaic:
            let rect = ScreenshotLayout.normalizedRect(px(stroke.start), px(stroke.end))
            if stroke.tool == .mosaic {
                drawMosaic(in: ctx, source: source, rect: rect, block: Int((ScreenshotLayout.mosaicBlock * scale).rounded()))
            } else {
                ctx.stroke(rect)
            }
        case .ellipse:
            ctx.strokeEllipse(in: ScreenshotLayout.normalizedRect(px(stroke.start), px(stroke.end)))
        case .line:
            ctx.beginPath()
            ctx.move(to: px(stroke.start))
            ctx.addLine(to: px(stroke.end))
            ctx.strokePath()
        case .arrow:
            let start = px(stroke.start)
            let end = px(stroke.end)
            ctx.beginPath()
            ctx.move(to: start)
            ctx.addLine(to: end)
            ctx.strokePath()
            let head = ScreenshotLayout.arrowHead(from: start, to: end)
            ctx.beginPath()
            ctx.move(to: end)
            ctx.addLine(to: head.0)
            ctx.addLine(to: head.1)
            ctx.closePath()
            ctx.fillPath()
        case .pen:
            let points = stroke.points.map(px)
            guard let first = points.first else { return }
            ctx.beginPath()
            ctx.move(to: first)
            for point in points.dropFirst() {
                ctx.addLine(to: point)
            }
            ctx.strokePath()
        case .text:
            drawText(stroke.text, at: px(stroke.start), color: color, fontSize: (16 + stroke.lineWidth) * scale, in: ctx)
        case .pin:
            drawPin(number: stroke.pinNumber, at: px(stroke.start), color: color, scale: scale, in: ctx)
        case .move, .crop:
            break
        }
    }

    private static func drawMosaic(in ctx: CGContext, source: CGImage, rect: CGRect, block: Int) {
        let integral = rect.integral.intersection(
            CGRect(x: 0, y: 0, width: source.width, height: source.height)
        )
        guard integral.width >= 1, integral.height >= 1,
              let piece = source.cropping(to: integral) else { return }
        let blockSize = max(4, block)
        let miniW = max(1, Int(integral.width) / blockSize)
        let miniH = max(1, Int(integral.height) / blockSize)
        guard let mini = CGContext(
            data: nil,
            width: miniW,
            height: miniH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        mini.interpolationQuality = .low
        mini.draw(piece, in: CGRect(x: 0, y: 0, width: miniW, height: miniH))
        guard let tiny = mini.makeImage() else { return }
        ctx.interpolationQuality = .none
        ctx.draw(tiny, in: integral)
        ctx.interpolationQuality = .high
    }

    private static func drawText(_ text: String, at origin: CGPoint, color: CGColor, fontSize: CGFloat, in ctx: CGContext) {
        guard !text.isEmpty else { return }
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        ctx.saveGState()
        // Glyphs are y-up; the context is y-down after the canvas flip.
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: origin.x, y: origin.y + fontSize)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private static func drawPin(number: Int, at center: CGPoint, color: CGColor, scale: CGFloat, in ctx: CGContext) {
        let radius: CGFloat = 11 * scale
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fillEllipse(in: rect)
        let label = "\(number)"
        let fontSize: CGFloat = 11 * scale
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: CGColor.white
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, [])
        ctx.saveGState()
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(
            x: center.x - bounds.width / 2,
            y: center.y + fontSize / 3
        )
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value & 0xFF0000) >> 16) / 255,
            green: CGFloat((value & 0x00FF00) >> 8) / 255,
            blue: CGFloat(value & 0x0000FF) / 255,
            alpha: 1
        )
    }
}
