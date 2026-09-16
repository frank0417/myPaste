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

    var title: String {
        switch self {
        case .move: return "调整选区"
        case .rect: return "矩形"
        case .ellipse: return "圆形"
        case .line: return "直线"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .text: return "文字"
        case .pin: return "序号"
        case .mosaic: return "马赛克"
        case .crop: return "重新选区"
        }
    }

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
    static let drag = "拖动工具条"
    static let color = "颜色"
    static let width = "粗细"
    static let undo = "撤销"
    static let download = "下载截图"
    static let cancel = "取消（Esc）"
    static let confirm = "完成（Enter）"
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
    static let toolbarSize = CGSize(width: 638, height: 48)
    /// Extra host height above the capsule so icon hover hints are not clipped.
    static let toolbarHintHeight: CGFloat = 28
    static let toolbarGap: CGFloat = 12
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
