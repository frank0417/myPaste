import AppKit
import Combine
import SwiftUI

/// Frozen-screen capture overlay: dim the display, drag a selection, annotate,
/// then confirm. One canvas panel per screen; the toolbar rides on the active one.
@MainActor
final class ScreenshotOverlayController {
    static let shared = ScreenshotOverlayController()

    enum Outcome {
        case cancelled
        case captured(png: Data, rawPNG: Data)
    }

    private var panels: [NSPanel] = []
    private var canvases: [ScreenshotCanvasView] = []
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var savedActivationPolicy: NSApplication.ActivationPolicy?
    private var lastRoutedEventNumber: Int = .min
    private var completion: ((Outcome) -> Void)?
    private var isPresenting = false

    private init() {}

    var isActive: Bool { isPresenting }

    func present(
        frames: [ScreenshotGrabber.Frame],
        mode: ScreenshotMode,
        recognizeText: Bool,
        completion: @escaping (Outcome) -> Void
    ) {
        dismissPanels()
        self.completion = completion
        isPresenting = true

        let mouse = NSEvent.mouseLocation
        for frame in frames {
            let session = ScreenshotSession(
                image: frame.image,
                cgImage: frame.cgImage,
                scale: frame.scale,
                canvasSize: frame.screen.frame.size,
                windows: frame.windows,
                mode: mode,
                recognizeText: recognizeText
            )
            if mode == .fullScreen {
                session.selection = CGRect(origin: .zero, size: frame.screen.frame.size)
            }
            let canvas = ScreenshotCanvasView(session: session)
            canvas.onConfirm = { [weak self] in self?.confirm(from: session) }
            canvas.onCancel = { [weak self] in self?.cancel() }
            canvas.onDownload = { [weak self] data in
                self?.download(data, thumbnail: session.thumbnail)
            }

            let panel = makePanel(on: frame.screen)
            panel.contentView = canvas
            panels.append(panel)
            canvases.append(canvas)
            panel.orderFrontRegardless()
        }

        installKeyMonitor()
        installMouseMonitors()
        becomeKeyForCapture()
        let active = panels.enumerated().first { _, panel in
            panel.screen?.frame.contains(mouse) == true
        }?.offset ?? 0
        if panels.indices.contains(active) {
            panels[active].makeKeyAndOrderFront(nil)
            canvases[active].window?.makeFirstResponder(canvases[active])
        }
    }

    func cancel() {
        finish(.cancelled)
    }

    private func confirm(from session: ScreenshotSession) {
        session.commitTextIfNeeded()
        guard let selection = session.selection, selection.width >= ScreenshotLayout.minSelection else { return }
        let strokes = session.recognizeText ? [] : session.strokes
        guard let annotated = ScreenshotRenderer.png(
            cgImage: session.cgImage,
            pointSize: session.canvasSize,
            selection: selection,
            strokes: strokes
        ) else {
            return
        }
        let raw: Data
        if strokes.isEmpty {
            raw = annotated
        } else {
            raw = ScreenshotRenderer.png(
                cgImage: session.cgImage,
                pointSize: session.canvasSize,
                selection: selection,
                strokes: []
            ) ?? annotated
        }
        finish(.captured(png: annotated, rawPNG: raw))
    }

    private func download(_ data: Data, thumbnail: NSImage?) {
        ScreenshotService.saveImage(
            data,
            suggestedName: ScreenshotService.downloadFileName(),
            thumbnail: thumbnail
        )
    }

    private func finish(_ outcome: Outcome) {
        guard isPresenting else { return }
        isPresenting = false
        let done = completion
        completion = nil
        dismissPanels()
        done?(outcome)
    }

    private func dismissPanels() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        for panel in panels {
            panel.orderOut(nil)
            panel.contentView = nil
        }
        panels.removeAll()
        canvases.removeAll()
        restoreActivationPolicy()
    }

    /// Accessory menu-bar apps swallow the first click as activation. Promote to a
    /// regular app for the overlay so the freeze is key and the first drag selects.
    private func becomeKeyForCapture() {
        if NSApp.activationPolicy() != .regular {
            savedActivationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func restoreActivationPolicy() {
        guard let savedActivationPolicy else { return }
        NSApp.setActivationPolicy(savedActivationPolicy)
        self.savedActivationPolicy = nil
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 53: // esc
                self.cancel()
                return nil
            case 36, 76: // return / keypad enter
                if let canvas = self.canvases.first(where: { $0.session.selection != nil }) {
                    self.confirm(from: canvas.session)
                    return nil
                }
                return event
            case 6 where event.modifierFlags.contains(.command): // ⌘Z
                self.canvases.first { $0.window?.isKeyWindow == true }?.session.undo()
                return nil
            default:
                return event
            }
        }
    }

    private func makePanel(on screen: NSScreen) -> NSPanel {
        let panel = ScreenshotOverlayPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        // NSPanel defaults to key-only-if-needed, so the first click would only
        // activate the freeze instead of starting a selection.
        panel.becomesKeyOnlyIfNeeded = false
        return panel
    }

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.routeOverlayMouse(event) ?? event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            _ = self?.routeOverlayMouse(event)
        }
    }

    /// First-click / background-app drags never reach the canvas view. Route them
    /// here so the freeze starts selecting immediately after the hotkey.
    private func routeOverlayMouse(_ event: NSEvent) -> NSEvent? {
        guard let canvas = canvas(for: event) else { return event }
        if event.eventNumber > 0, event.eventNumber == lastRoutedEventNumber {
            return nil
        }
        if canvas.shouldLetSubviewHandle(event) {
            return event
        }
        if event.eventNumber > 0 {
            lastRoutedEventNumber = event.eventNumber
        }
        switch event.type {
        case .leftMouseDown:
            canvas.mouseDown(with: event)
        case .leftMouseDragged:
            canvas.mouseDragged(with: event)
        case .leftMouseUp:
            canvas.mouseUp(with: event)
        default:
            return event
        }
        return nil
    }

    private func canvas(for event: NSEvent) -> ScreenshotCanvasView? {
        if let window = event.window,
           let match = canvases.first(where: { $0.window === window }) {
            return match
        }
        let screenPoint: CGPoint
        if let window = event.window {
            screenPoint = window.convertPoint(toScreen: event.locationInWindow)
        } else {
            screenPoint = event.locationInWindow
        }
        return canvases.first { $0.window?.frame.contains(screenPoint) == true }
    }
}

private final class ScreenshotOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { true }
}

final class ScreenshotSession: ObservableObject {
    let image: NSImage
    let cgImage: CGImage
    let scale: CGFloat
    let canvasSize: CGSize
    let windows: [CGRect]
    let mode: ScreenshotMode
    let recognizeText: Bool

    @Published var selection: CGRect?
    @Published var tool: ScreenshotTool = .move
    @Published var colorHex: String = ScreenshotLayout.defaultColorHex
    @Published var lineWidth: CGFloat = 3
    @Published var strokes: [ScreenshotStroke] = []
    @Published var current: ScreenshotStroke?
    @Published var hoveredWindow: CGRect?
    @Published var pinCounter: Int = 1
    @Published var toolbarOffset: CGSize = .zero
    @Published var showColorPicker = false
    @Published var showWidthPicker = false
    @Published var showOCRResult = false
    @Published var ocrResult: String?
    @Published var isRecognizing = false

    var onChange: (() -> Void)?
    fileprivate weak var canvas: ScreenshotCanvasView?

    var thumbnail: NSImage? { image }

    init(
        image: NSImage,
        cgImage: CGImage,
        scale: CGFloat,
        canvasSize: CGSize,
        windows: [CGRect],
        mode: ScreenshotMode,
        recognizeText: Bool
    ) {
        self.image = image
        self.cgImage = cgImage
        self.scale = scale
        self.canvasSize = canvasSize
        self.windows = windows
        self.mode = mode
        self.recognizeText = recognizeText
    }

    func notify() {
        onChange?()
    }

    func undo() {
        commitTextIfNeeded()
        if current != nil {
            current = nil
        } else if !strokes.isEmpty {
            strokes.removeLast()
        }
        notify()
    }

    func commitTextIfNeeded() {
        canvas?.commitText()
    }
}

private enum DragKind {
    case idle
    case newSelection
    case move
    case handle(ScreenshotHandle)
    case draw
}

final class ScreenshotCanvasView: NSView, NSTextFieldDelegate {
    let session: ScreenshotSession
    var onConfirm: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDownload: ((Data) -> Void)?

    private var dragKind: DragKind = .idle
    private var dragStart: CGPoint = .zero
    private var selectionAtDragStart: CGRect = .zero
    private var toolbarHost: NSHostingView<ScreenshotToolbarView>?
    private var ocrHost: NSHostingView<ScreenshotOCRPanelView>?
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var tracking: NSTrackingArea?

    init(session: ScreenshotSession) {
        self.session = session
        super.init(frame: CGRect(origin: .zero, size: session.canvasSize))
        session.canvas = self
        session.onChange = { [weak self] in
            guard let self else { return }
            self.needsDisplay = true
            self.window?.invalidateCursorRects(for: self)
            self.positionChrome()
        }
        wantsLayer = true
        let toolbar = NSHostingView(rootView: ScreenshotToolbarView(
            session: session,
            onConfirm: { [weak self] in self?.onConfirm?() },
            onCancel: { [weak self] in self?.onCancel?() },
            onUndo: { [weak self] in self?.session.undo() },
            onDownload: { [weak self] in self?.downloadCurrent() },
            onRecognize: { [weak self] in self?.recognizeSelection() },
            onLayout: { [weak self] in self?.positionChrome() }
        ))
        toolbar.frame = .zero
        toolbar.clipsToBounds = false
        addSubview(toolbar)
        toolbarHost = toolbar

        let ocr = NSHostingView(rootView: ScreenshotOCRPanelView(
            session: session,
            onCopy: { [weak self] text in self?.copyOCRText(text) },
            onDismiss: { [weak self] in self?.dismissOCRPanel() }
        ))
        ocr.frame = .zero
        ocr.clipsToBounds = false
        addSubview(ocr)
        ocrHost = ocr
        positionChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { true }

    /// Without this, the first click after the hotkey only activates the freeze.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Toolbar / text field keep their own clicks; a live drag stays on the canvas
    /// even if the pointer crosses the strip.
    func shouldLetSubviewHandle(_ event: NSEvent) -> Bool {
        guard case .idle = dragKind else { return false }
        let point = canvasPoint(from: event)
        if let field = textField, field.frame.contains(point) { return true }
        if let toolbarHost, !toolbarHost.isHidden, toolbarHost.frame.contains(point) {
            return true
        }
        if let ocrHost, !ocrHost.isHidden, ocrHost.frame.contains(point) {
            return true
        }
        return false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        positionChrome()
    }

    override func layout() {
        super.layout()
        positionChrome()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if let selection = session.selection, session.tool == .move {
            addCursorRect(selection, cursor: .openHand)
        }
        if let toolbarHost, !toolbarHost.isHidden {
            addCursorRect(toolbarHost.frame, cursor: .openHand)
        }
        if let ocrHost, !ocrHost.isHidden {
            addCursorRect(ocrHost.frame, cursor: .iBeam)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let toolbarHost, !toolbarHost.isHidden, toolbarHost.frame.contains(point) {
            return
        }
        if let ocrHost, !ocrHost.isHidden, ocrHost.frame.contains(point) {
            return
        }
        if let selection = session.selection, session.tool == .move, selection.contains(point) {
            NSCursor.openHand.set()
            return
        }
        NSCursor.crosshair.set()
    }

    /// Blit the captured CGImage at native pixels. Going through NSImage in a
    /// flipped view can rasterize at 1x and look soft on Retina.
    private func drawFreeze() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .none
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(session.cgImage, in: bounds)
        ctx.restoreGState()
    }

    override func draw(_ dirtyRect: NSRect) {
        drawFreeze()

        let dim = NSBezierPath(rect: bounds)
        if let selection = session.selection {
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(ScreenshotLayout.dimOpacity).setFill()
        dim.fill()

        if session.selection == nil, let hovered = session.hoveredWindow {
            NSColor.white.withAlphaComponent(0.1).setFill()
            NSBezierPath(rect: hovered).fill()
            selectionColor.setStroke()
            let outline = NSBezierPath(rect: hovered)
            outline.lineWidth = 2
            outline.stroke()
        }

        guard let selection = session.selection else { return }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        for stroke in session.strokes {
            drawStroke(stroke)
        }
        if let current = session.current {
            drawStroke(current)
        }
        NSGraphicsContext.restoreGraphicsState()

        selectionColor.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 1.5
        border.stroke()

        NSColor.white.setStroke()
        for origin in ScreenshotLayout.handlePoints(in: selection).values {
            let halo = CGRect(x: origin.x - 5, y: origin.y - 5, width: 10, height: 10)
            NSBezierPath(ovalIn: halo).fill(using: NSColor.white)
            selectionColor.setFill()
            let inner = CGRect(x: origin.x - ScreenshotLayout.handleRadius, y: origin.y - ScreenshotLayout.handleRadius, width: ScreenshotLayout.handleRadius * 2, height: ScreenshotLayout.handleRadius * 2)
            NSBezierPath(ovalIn: inner).fill()
            NSColor.white.setFill()
        }

        drawSizeBadge(for: selection)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard session.selection == nil, session.mode == .window else { return }
        let next = ScreenshotLayout.window(at: point, windows: session.windows)
        if next != session.hoveredWindow {
            session.hoveredWindow = next
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitText()
        session.showColorPicker = false
        session.showWidthPicker = false
        session.showOCRResult = false
        let point = canvasPoint(from: event)
        if event.clickCount == 2, session.selection?.contains(point) == true {
            onConfirm?()
            return
        }
        dragStart = point

        if let selection = session.selection {
            if let handle = ScreenshotLayout.hitTest(point, selection: selection), handle != .move {
                dragKind = .handle(handle)
                selectionAtDragStart = selection
                return
            }
            if session.tool == .crop {
                beginNewSelection(at: point)
                return
            }
            if handleInsideSelection(point, selection: selection) {
                if session.tool.isStamp {
                    stamp(at: point)
                    dragKind = .idle
                    return
                }
                if session.tool.isDrawable {
                    beginDraw(at: point)
                    return
                }
                dragKind = .move
                selectionAtDragStart = selection
                return
            }
        } else if session.mode == .window,
                  let hovered = ScreenshotLayout.window(at: point, windows: session.windows) {
            session.selection = hovered.intersection(bounds)
            session.hoveredWindow = nil
            dragKind = .idle
            session.notify()
            return
        }

        beginNewSelection(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = canvasPoint(from: event)
        let shift = event.modifierFlags.contains(.shift)
        switch dragKind {
        case .idle:
            break
        case .newSelection:
            var rect = ScreenshotLayout.normalizedRect(dragStart, point)
            if shift {
                let end = ScreenshotLayout.snapEnd(from: dragStart, to: point, tool: .rect, shift: true)
                rect = ScreenshotLayout.normalizedRect(dragStart, end)
            }
            session.selection = ScreenshotLayout.clamp(rect, to: bounds)
            session.notify()
        case .move:
            let delta = CGSize(width: point.x - dragStart.x, height: point.y - dragStart.y)
            session.selection = ScreenshotLayout.move(selectionAtDragStart, by: delta, bounds: bounds)
            session.notify()
        case .handle(let handle):
            session.selection = ScreenshotLayout.resize(selectionAtDragStart, handle: handle, to: point, bounds: bounds)
            session.notify()
        case .draw:
            guard var current = session.current else { return }
            if current.tool == .pen {
                current.points.append(point)
            } else {
                let end = ScreenshotLayout.snapEnd(from: current.start, to: point, tool: current.tool, shift: shift)
                if current.points.count == 1 {
                    current.points.append(end)
                } else {
                    current.points[1] = end
                }
            }
            session.current = current
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch dragKind {
        case .newSelection:
            if let selection = session.selection,
               selection.width < ScreenshotLayout.minSelection || selection.height < ScreenshotLayout.minSelection {
                session.selection = nil
                session.notify()
            }
        case .draw:
            if let current = session.current {
                session.strokes.append(current)
                session.current = nil
                session.notify()
            }
        default:
            break
        }
        dragKind = .idle
        window?.invalidateCursorRects(for: self)
        positionChrome()
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    func commitText() {
        guard let field = textField else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        textField = nil
        window?.makeFirstResponder(self)
        guard !value.isEmpty else { return }
        session.strokes.append(
            ScreenshotStroke(
                tool: .text,
                colorHex: session.colorHex,
                lineWidth: session.lineWidth,
                points: [textOrigin],
                text: value
            )
        )
        session.notify()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
    }

    private func beginNewSelection(at point: CGPoint) {
        commitText()
        session.strokes = []
        session.current = nil
        session.toolbarOffset = .zero
        session.tool = .move
        session.pinCounter = 1
        session.showOCRResult = false
        session.ocrResult = nil
        session.isRecognizing = false
        dragKind = .newSelection
        session.selection = CGRect(origin: point, size: .zero)
        session.notify()
    }

    private func handleInsideSelection(_ point: CGPoint, selection: CGRect) -> Bool {
        ScreenshotLayout.hitTest(point, selection: selection) == .move
    }

    private func beginDraw(at point: CGPoint) {
        dragKind = .draw
        session.current = ScreenshotStroke(
            tool: session.tool,
            colorHex: session.colorHex,
            lineWidth: session.lineWidth,
            points: [point, point]
        )
        needsDisplay = true
    }

    private func stamp(at point: CGPoint) {
        if session.tool == .text {
            beginText(at: point)
            return
        }
        session.strokes.append(
            ScreenshotStroke(
                tool: .pin,
                colorHex: session.colorHex,
                lineWidth: session.lineWidth,
                points: [point],
                pinNumber: session.pinCounter
            )
        )
        session.pinCounter += 1
        session.notify()
    }

    private func beginText(at point: CGPoint) {
        commitText()
        textOrigin = point
        let field = NSTextField(frame: CGRect(x: point.x, y: point.y, width: 240, height: 28))
        field.font = .systemFont(ofSize: 16 + session.lineWidth, weight: .medium)
        field.textColor = NSColor(hex: session.colorHex) ?? .systemRed
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.placeholderString = ScreenshotL10n.string(.textPlaceholder)
        field.delegate = self
        addSubview(field)
        textField = field
        window?.makeFirstResponder(field)
    }

    private func downloadCurrent() {
        commitText()
        guard let selection = session.selection,
              let data = ScreenshotRenderer.png(
                cgImage: session.cgImage,
                pointSize: session.canvasSize,
                selection: selection,
                strokes: session.recognizeText ? [] : session.strokes
              ) else { return }
        onDownload?(data)
    }

    private func recognizeSelection() {
        guard !session.isRecognizing else { return }
        commitText()
        guard let selection = session.selection,
              selection.width >= ScreenshotLayout.minSelection,
              selection.height >= ScreenshotLayout.minSelection,
              let data = ScreenshotRenderer.png(
                cgImage: session.cgImage,
                pointSize: session.canvasSize,
                selection: selection,
                strokes: []
              ) else { return }
        session.isRecognizing = true
        session.showOCRResult = true
        session.ocrResult = nil
        Task { [session] in
            let text = await Task.detached(priority: .userInitiated) {
                TextRecognizer.recognize(imageData: data)
            }.value
            await MainActor.run {
                session.isRecognizing = false
                session.ocrResult = text
                session.showOCRResult = true
                session.notify()
            }
        }
    }

    private func copyOCRText(_ text: String) {
        let snippet = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty else { return }
        ClipboardMonitor.shared.ignoreNextPasteboardChange()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(snippet, forType: .string)
    }

    private func dismissOCRPanel() {
        session.showOCRResult = false
        session.ocrResult = nil
        session.isRecognizing = false
        session.notify()
    }

    private func canvasPoint(from event: NSEvent) -> CGPoint {
        if event.window == nil {
            guard let window else { return .zero }
            let windowPoint = window.convertPoint(fromScreen: event.locationInWindow)
            return convert(windowPoint, from: nil)
        }
        if event.window !== window, let source = event.window, let window {
            let screenPoint = source.convertPoint(toScreen: event.locationInWindow)
            let windowPoint = window.convertPoint(fromScreen: screenPoint)
            return convert(windowPoint, from: nil)
        }
        return convert(event.locationInWindow, from: nil)
    }

    private func positionChrome() {
        positionToolbar()
        positionOCRPanel()
    }

    private func positionToolbar() {
        guard let toolbarHost else { return }
        guard let selection = session.selection, selection.width >= 8 else {
            toolbarHost.isHidden = true
            return
        }
        toolbarHost.isHidden = false
        toolbarHost.clipsToBounds = false
        let size = session.recognizeText
            ? CGSize(width: 220, height: ScreenshotLayout.toolbarSize.height)
            : ScreenshotLayout.toolbarSize
        toolbarHost.frame = ScreenshotLayout.toolbarFrame(
            selection: selection,
            canvas: bounds,
            size: size,
            offset: session.toolbarOffset
        )
    }

    private func positionOCRPanel() {
        guard let ocrHost else { return }
        let visible = session.showOCRResult || session.isRecognizing
        guard visible, let selection = session.selection, selection.width >= 8 else {
            ocrHost.isHidden = true
            return
        }
        ocrHost.isHidden = false
        let height = ScreenshotLayout.ocrPanelHeight(for: selection, canvas: bounds)
        ocrHost.frame = ScreenshotLayout.ocrPanelFrame(
            selection: selection,
            canvas: bounds,
            size: CGSize(width: ScreenshotLayout.ocrPanelSize.width, height: height)
        )
    }

    private var selectionColor: NSColor {
        NSColor(hex: ScreenshotLayout.selectionColorHex) ?? .systemBlue
    }

    private func drawStroke(_ stroke: ScreenshotStroke) {
        let color = NSColor(hex: stroke.colorHex) ?? .systemRed
        color.setStroke()
        color.setFill()
        let width = stroke.lineWidth
        switch stroke.tool {
        case .rect:
            let path = NSBezierPath(rect: stroke.bounds)
            path.lineWidth = width
            path.stroke()
        case .ellipse:
            let path = NSBezierPath(ovalIn: stroke.bounds)
            path.lineWidth = width
            path.stroke()
        case .line:
            let path = NSBezierPath()
            path.move(to: stroke.start)
            path.line(to: stroke.end)
            path.lineWidth = width
            path.lineCapStyle = .round
            path.stroke()
        case .arrow:
            let path = NSBezierPath()
            path.move(to: stroke.start)
            path.line(to: stroke.end)
            path.lineWidth = width
            path.lineCapStyle = .round
            path.stroke()
            let head = ScreenshotLayout.arrowHead(from: stroke.start, to: stroke.end)
            let triangle = NSBezierPath()
            triangle.move(to: stroke.end)
            triangle.line(to: head.0)
            triangle.line(to: head.1)
            triangle.close()
            triangle.fill()
        case .pen:
            guard let first = stroke.points.first else { return }
            let path = NSBezierPath()
            path.move(to: first)
            for point in stroke.points.dropFirst() {
                path.line(to: point)
            }
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        case .text:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16 + stroke.lineWidth, weight: .medium),
                .foregroundColor: color
            ]
            (stroke.text as NSString).draw(at: stroke.start, withAttributes: attrs)
        case .pin:
            let rect = stroke.bounds
            NSBezierPath(ovalIn: rect).fill()
            let label = "\(stroke.pinNumber)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let size = label.size(withAttributes: attrs)
            label.draw(
                at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                withAttributes: attrs
            )
        case .mosaic:
            drawMosaicPreview(in: stroke.bounds)
        case .move, .crop:
            break
        }
    }

    private func drawMosaicPreview(in rect: CGRect) {
        let block = ScreenshotLayout.mosaicBlock
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                let sample = CGPoint(x: min(x + block / 2, rect.maxX - 1), y: min(y + block / 2, rect.maxY - 1))
                colorAt(sample).setFill()
                NSBezierPath(rect: CGRect(x: x, y: y, width: block, height: block).intersection(rect)).fill()
                x += block
            }
            y += block
        }
    }

    private func colorAt(_ point: CGPoint) -> NSColor {
        let source = session.cgImage
        let scale = CGFloat(source.width) / max(bounds.width, 1)
        let px = min(max(Int(point.x * scale), 0), source.width - 1)
        let py = min(max(Int(point.y * scale), 0), source.height - 1)
        guard source.bitsPerPixel >= 24,
              let data = source.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return .gray
        }
        let bytesPerPixel = max(1, source.bitsPerPixel / 8)
        let offset = py * source.bytesPerRow + px * bytesPerPixel
        guard offset + 2 < CFDataGetLength(data) else { return .gray }
        let r = CGFloat(ptr[offset]) / 255
        let g = CGFloat(ptr[offset + 1]) / 255
        let b = CGFloat(ptr[offset + 2]) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private func drawSizeBadge(for selection: CGRect) {
        let text = ScreenshotLayout.sizeLabel(width: selection.width, height: selection.height)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let frame = ScreenshotLayout.sizeBadgeFrame(selection: selection, canvas: bounds, textWidth: size.width)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4).fill()
        let textOrigin = CGPoint(
            x: frame.minX + (frame.width - size.width) / 2,
            y: frame.minY + (frame.height - size.height) / 2
        )
        (text as NSString).draw(at: textOrigin, withAttributes: attrs)
    }
}

private extension NSBezierPath {
    func fill(using color: NSColor) {
        color.setFill()
        fill()
    }
}

private struct ScreenshotToolbarView: View {
    @ObservedObject var session: ScreenshotSession
    var onConfirm: () -> Void
    var onCancel: () -> Void
    var onUndo: () -> Void
    var onDownload: () -> Void
    var onRecognize: () -> Void
    var onLayout: () -> Void
    @State private var toolbarDragStart: CGSize = .zero
    @State private var isDraggingToolbar = false

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: ScreenshotLayout.toolbarHintHeight)
                .allowsHitTesting(false)
            HStack(spacing: 2) {
                dragHandle
                if !session.recognizeText {
                    ForEach(ScreenshotTool.toolbarTools) { tool in
                        toolButton(tool)
                    }
                    divider
                    colorButton
                    widthButton
                    divider
                    iconButton(ScreenshotToolbarHintText.undo, systemImage: "arrow.uturn.backward", action: onUndo)
                        .disabled(session.strokes.isEmpty && session.current == nil)
                    iconButton(ScreenshotToolbarHintText.download, systemImage: "arrow.down.to.line", action: onDownload)
                    recognizeButton
                    divider
                }
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: "#F5222D") ?? .red)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .screenshotToolbarHint(ScreenshotToolbarHintText.cancel)
                .screenshotToolbarPointer(.pointingHand)
                Button(action: onConfirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(hex: "#52C41A") ?? .green)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .screenshotToolbarHint(ScreenshotToolbarHintText.confirm)
                .screenshotToolbarPointer(.pointingHand)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: ScreenshotLayout.toolbarSize.height)
            .contentShape(Capsule())
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).fill(Color.white.opacity(0.92)))
            }
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .simultaneousGesture(toolbarDragGesture)
            .popover(isPresented: $session.showColorPicker, arrowEdge: .top) {
                HStack(spacing: 8) {
                    ForEach(ScreenshotLayout.palette, id: \.self) { hex in
                        Button {
                            session.colorHex = hex
                            session.showColorPicker = false
                        } label: {
                            Circle()
                                .fill(Color(hex: hex) ?? .red)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle().strokeBorder(
                                        session.colorHex == hex ? Color.primary : Color.black.opacity(0.15),
                                        lineWidth: session.colorHex == hex ? 2 : 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                        .screenshotToolbarPointer(.pointingHand)
                    }
                }
                .padding(10)
            }
            .popover(isPresented: $session.showWidthPicker, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ScreenshotLayout.lineWidths, id: \.self) { width in
                        Button {
                            session.lineWidth = width
                            session.showWidthPicker = false
                        } label: {
                            HStack {
                                Capsule().frame(width: 72, height: width)
                                if session.lineWidth == width {
                                    Image(systemName: "checkmark").font(.caption)
                                }
                            }
                            .foregroundStyle(Color.primary)
                        }
                        .buttonStyle(.plain)
                        .screenshotToolbarPointer(.pointingHand)
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var toolbarDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isDraggingToolbar {
                    isDraggingToolbar = true
                    toolbarDragStart = session.toolbarOffset
                    NSCursor.closedHand.set()
                }
                session.toolbarOffset = CGSize(
                    width: toolbarDragStart.width + value.translation.width,
                    height: toolbarDragStart.height + value.translation.height
                )
                onLayout()
            }
            .onEnded { _ in
                isDraggingToolbar = false
                toolbarDragStart = session.toolbarOffset
                NSCursor.openHand.set()
            }
    }

    private var dragHandle: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(90))
            .frame(width: 22, height: 32)
            .contentShape(Rectangle())
            .screenshotToolbarHint(ScreenshotToolbarHintText.drag)
            .screenshotToolbarPointer(.openHand)
    }

    private func toolButton(_ tool: ScreenshotTool) -> some View {
        Button {
            session.tool = session.tool == tool ? .move : tool
            session.notify()
        } label: {
            Image(systemName: tool.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(session.tool == tool ? Color.white : Color.primary.opacity(0.78))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(session.tool == tool ? Color(hex: ScreenshotLayout.selectionColorHex) ?? .blue : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .screenshotToolbarHint(tool.title)
        .screenshotToolbarPointer(.pointingHand)
    }

    private func iconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.78))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .screenshotToolbarHint(title)
        .screenshotToolbarPointer(.pointingHand)
    }

    private var recognizeButton: some View {
        Button(action: onRecognize) {
            Group {
                if session.isRecognizing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundStyle(Color.primary.opacity(0.78))
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(session.isRecognizing)
        .screenshotToolbarHint(ScreenshotToolbarHintText.recognizeText)
        .screenshotToolbarPointer(.pointingHand)
    }

    private var colorButton: some View {
        Button {
            session.showWidthPicker = false
            session.showColorPicker.toggle()
        } label: {
            Circle()
                .fill(Color(hex: session.colorHex) ?? .red)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 1))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .screenshotToolbarHint(ScreenshotToolbarHintText.color)
        .screenshotToolbarPointer(.pointingHand)
    }

    private var widthButton: some View {
        Button {
            session.showColorPicker = false
            session.showWidthPicker.toggle()
        } label: {
            Image(systemName: "lineweight")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.78))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .screenshotToolbarHint(ScreenshotToolbarHintText.width)
        .screenshotToolbarPointer(.pointingHand)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 4)
    }
}

/// Immediate hover caption above a toolbar icon. Native `.help()` is kept for
/// VoiceOver, but screen-saver overlay panels often never show that tooltip.
private struct ScreenshotToolbarHintModifier: ViewModifier {
    let title: String
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .overlay(alignment: .top) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.black.opacity(0.78))
                    )
                    .fixedSize()
                    .offset(y: hintOffset)
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .zIndex(hovering ? 1 : 0)
            .help(title)
    }

    /// Place the 22pt bubble in the host's hint band, 6pt above the capsule.
    private var hintOffset: CGFloat {
        let buttonInset = (ScreenshotLayout.toolbarSize.height - 32) / 2
        return -(buttonInset + ScreenshotLayout.toolbarHintHeight)
    }
}

private struct ScreenshotToolbarPointerModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                cursor.set()
            }
        }
    }
}

private extension View {
    func screenshotToolbarHint(_ title: String) -> some View {
        modifier(ScreenshotToolbarHintModifier(title: title))
    }

    func screenshotToolbarPointer(_ cursor: NSCursor) -> some View {
        modifier(ScreenshotToolbarPointerModifier(cursor: cursor))
    }
}

/// Recognized text sits to the right of the crop. The user can highlight a
/// substring, then copy that (or the whole result) without ending the capture.
private struct ScreenshotOCRPanelView: View {
    @ObservedObject var session: ScreenshotSession
    var onCopy: (String) -> Void
    var onDismiss: () -> Void
    @State private var selectedText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ScreenshotL10n.string(.recognizeText))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Group {
                if session.isRecognizing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let text = session.ocrResult, !text.isEmpty {
                    ScreenshotOCRTextView(text: text, selectedText: $selectedText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text(ScreenshotL10n.string(.ocrEmpty))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 12)
                }
            }

            HStack(spacing: 8) {
                Button(action: onDismiss) {
                    Text(ScreenshotL10n.string(.ocrDismiss))
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .screenshotToolbarPointer(.pointingHand)

                Spacer(minLength: 0)

                Button {
                    let selected = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onCopy(selected.isEmpty ? (session.ocrResult ?? "") : selected)
                } label: {
                    Text(ScreenshotL10n.string(.copy))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color(hex: ScreenshotLayout.selectionColorHex) ?? .blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled((session.ocrResult ?? "").isEmpty)
                .opacity((session.ocrResult ?? "").isEmpty ? 0.45 : 1)
                .screenshotToolbarPointer(.pointingHand)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.94))
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .onChange(of: session.ocrResult) { _, _ in
            selectedText = ""
        }
    }
}

private struct ScreenshotOCRTextView: NSViewRepresentable {
    let text: String
    @Binding var selectedText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedText: $selectedText)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 4)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = text

        scroll.documentView = textView
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.selectedText = $selectedText
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var selectedText: Binding<String>
        weak var textView: NSTextView?

        init(selectedText: Binding<String>) {
            self.selectedText = selectedText
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            if range.length > 0, NSMaxRange(range) <= (textView.string as NSString).length {
                selectedText.wrappedValue = (textView.string as NSString).substring(with: range)
            } else {
                selectedText.wrappedValue = ""
            }
        }
    }
}
