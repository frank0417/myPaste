import AppKit
import SwiftUI
import SwiftData
import QuartzCore

/// Menu-bar status item + bottom floating clipboard shelf.
/// Closing the panel only hides it — the app stays resident for the global hotkey.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    static let shared = StatusItemController()

    static let panelWidth: CGFloat = 980
    static let panelHeight: CGFloat = 390
    /// Tall enough for the detail overlay (header + body + footer) without clipping.
    static let detailPanelHeight: CGFloat = 600

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    /// The SwiftUI `Window` scene's window, handed over by `ContentView`. Held strongly so
    /// the hotkey can bring it back after the user closes it.
    private var mainWindow: NSWindow?
    private var modelContainer: ModelContainer?
    private var appState: AppState?
    private var localKeyMonitor: Any?
    private var localClickMonitor: Any?
    private var isDetailExpanded = false

    private override init() {
        super.init()
    }

    func install(container: ModelContainer, appState: AppState) {
        self.modelContainer = container
        self.appState = appState

        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                let image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "PasteNest")
                image?.isTemplate = true
                button.image = image
                button.toolTip = "PasteNest — 常驻后台（\(appState.hotkeyDisplay) 唤出）"
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            statusItem = item
        }

        if panel == nil {
            panel = makePanel()
        }
    }

    /// Keeps the status-item tooltip in sync after the user changes the shortcut.
    func refreshHotkeyHint(_ display: String) {
        statusItem?.button?.toolTip = "PasteNest — 常驻后台（\(display) 唤出）"
    }

    /// `ScreenshotService` hides the shelf before a capture and restores it after.
    var isPanelVisible: Bool {
        panel?.isVisible == true
    }

    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        window.isReleasedWhenClosed = false
        mainWindow = window
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()
        let panelHint = appState.map { "（\($0.hotkeyDisplay)）" } ?? ""
        let windowHint = appState.map { "（\($0.mainWindowHotkeyDisplay)）" } ?? ""
        menu.addItem(withTitle: "显示剪贴板面板\(panelHint)", action: #selector(menuShowPanel), keyEquivalent: "")
        menu.addItem(withTitle: "显示主窗口\(windowHint)", action: #selector(menuShowMainWindow), keyEquivalent: "")
        menu.addItem(withTitle: "隐藏面板", action: #selector(menuHidePanel), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        let shotHint = appState.map { "（\($0.screenshotHotkeyDisplay)）" } ?? ""
        let ocrHint = appState.map { "（\($0.screenshotOCRHotkeyDisplay)）" } ?? ""
        menu.addItem(withTitle: "截取区域\(shotHint)", action: #selector(menuCaptureRegion), keyEquivalent: "")
        menu.addItem(withTitle: "截取窗口", action: #selector(menuCaptureWindow), keyEquivalent: "")
        menu.addItem(withTitle: "截取整屏", action: #selector(menuCaptureFullScreen), keyEquivalent: "")
        menu.addItem(withTitle: "截取区域并识字\(ocrHint)", action: #selector(menuCaptureRegionOCR), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "快捷键设置…", action: #selector(menuOpenHotkeySettings), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 PasteNest", action: #selector(menuQuit), keyEquivalent: "q")
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach so left-click keeps toggling the panel.
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    @objc private func menuShowPanel() { showPanel() }
    @objc private func menuShowMainWindow() { showMainWindow() }
    @objc private func menuHidePanel() { hidePanel() }
    @objc private func menuCaptureRegion() { ScreenshotService.shared.capture(.region) }
    @objc private func menuCaptureWindow() { ScreenshotService.shared.capture(.window) }
    @objc private func menuCaptureFullScreen() { ScreenshotService.shared.capture(.fullScreen) }
    @objc private func menuCaptureRegionOCR() { ScreenshotService.shared.capture(.region, recognizeText: true) }
    @objc private func menuOpenSettings() {
        openSettings()
    }
    @objc private func menuOpenHotkeySettings() {
        openSettings(tab: .hotkeys)
    }

    /// Bring up the SwiftUI Settings scene from an accessory (menu-bar) app.
    /// The panel is a non-activating NSPanel, so the settings window must be
    /// ordered in explicitly after the app activates, or it never appears.
    /// - Parameter tab: the tab to land on; `nil` keeps whatever was showing.
    func openSettings(tab: AppState.SettingsTab? = nil) {
        if let tab {
            appState?.settingsTab = tab
        }
        hidePanel()
        // Activate first so the settings window can come to the front.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            if #available(macOS 14, *) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } else {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            // The scene window is created lazily; nudge it frontmost on the
            // next runloop turn once it exists.
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                // Only bring forward the settings window itself. Ordering every plain
                // window in also raised the main window's leftover blank surface.
                for window in NSApp.windows where !(window is NSPanel) && window !== self.mainWindow {
                    guard !window.title.isEmpty else { continue }
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    func togglePanel() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    /// The shelf and the main window are mutually exclusive surfaces.
    func toggleMainWindow() {
        guard let window = resolveMainWindow() else { return }
        if window.isVisible && NSApp.isActive {
            hideMainWindow()
        } else {
            showMainWindow()
        }
    }

    func showMainWindow() {
        hidePanel()
        guard let window = resolveMainWindow() else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func hideMainWindow() {
        guard let window = resolveMainWindow(), window.isVisible else { return }
        window.orderOut(nil)
    }

    /// `ContentView` registers the window once it exists; fall back to a lookup when the
    /// scene hasn't rendered yet (the Settings window must never be mistaken for it).
    private func resolveMainWindow() -> NSWindow? {
        if let mainWindow { return mainWindow }
        let found = NSApp.windows.first { window in
            guard !(window is NSPanel), window.canBecomeMain else { return false }
            if let identifier = window.identifier?.rawValue {
                return !identifier.contains("Settings") && identifier.contains("main")
            }
            return window.title == "PasteNest"
        }
        mainWindow = found
        return found
    }

    func showPanel() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        hideMainWindow()

        let expanded = appState?.shelfDetailItemID != nil
        isDetailExpanded = expanded
        if let container = modelContainer, let appState {
            panel.contentView = makeHostingView(container: container, appState: appState, expanded: expanded)
        }

        // Always stay a menu-bar agent — never promote to Dock app just to show UI.
        NSApp.setActivationPolicy(.accessory)
        positionPanel(panel, expanded: expanded)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        installDismissalMonitors()
    }

    func hidePanel() {
        removeDismissalMonitors()
        appState?.shelfDetailItemID = nil
        closePanelSearch()
        isDetailExpanded = false
        panel?.orderOut(nil)
    }

    /// The shelf always reopens without the search field; the query would otherwise
    /// keep filtering a panel whose search box is gone.
    private func closePanelSearch() {
        guard let appState, appState.isPanelSearchVisible else { return }
        appState.isPanelSearchVisible = false
        appState.searchQuery = ""
    }

    /// Grow the floating shelf so the detail overlay is fully visible.
    func setExpandedForDetail(_ expanded: Bool) {
        guard isDetailExpanded != expanded else {
            if expanded, let panel, panel.isVisible {
                // Re-layout if already expanded but frame drifted.
                positionPanel(panel, expanded: true)
            }
            return
        }
        isDetailExpanded = expanded
        guard let panel, panel.isVisible else { return }
        if let container = modelContainer, let appState {
            panel.contentView = makeHostingView(container: container, appState: appState, expanded: expanded)
        }
        positionPanel(panel, expanded: expanded)
    }

    private func makePanel() -> NSPanel {
        // ClipboardShelfPanel overrides `canBecomeKey` — a borderless NSPanel
        // otherwise refuses to become key, and the search field cannot type.
        let panel = ClipboardShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // SwiftUI draws the shelf shadow; a window shadow leaves a rectangular strip below.
        panel.hasShadow = false
        panel.delegate = self

        if let container = modelContainer, let appState {
            panel.contentView = makeHostingView(container: container, appState: appState, expanded: false)
        }

        return panel
    }

    private func makeHostingView(container: ModelContainer, appState: AppState, expanded: Bool) -> NSView {
        let height = expanded ? Self.detailPanelHeight : Self.panelHeight
        let root = MenuBarPanel()
            .environmentObject(appState)
            .modelContainer(container)
            .frame(width: Self.panelWidth, height: height)
        let hosting = NSHostingView(rootView: root)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        return hosting
    }

    private func positionPanel(_ panel: NSPanel, expanded: Bool) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        let width = min(Self.panelWidth, visible.width - 24)
        let preferredHeight = expanded ? Self.detailPanelHeight : Self.panelHeight
        let height = min(preferredHeight, visible.height - 36)
        let x = visible.midX - width / 2
        // Grow upward from the bottom shelf position.
        let y = visible.minY + 18
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(
                NSRect(x: x, y: y, width: width, height: height),
                display: true
            )
        }
    }

    private func installDismissalMonitors() {
        removeDismissalMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                if self?.appState?.shelfDetailItemID != nil {
                    self?.appState?.shelfDetailItemID = nil
                    self?.setExpandedForDetail(false)
                    return nil
                }
                // Escape backs out of search before it dismisses the whole shelf.
                // The panel clears its draft text when the box closes.
                if let appState = self?.appState, appState.isPanelSearchVisible {
                    appState.isPanelSearchVisible = false
                    return nil
                }
                self?.hidePanel()
                return nil
            }
            return event
        }

        localClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return }
            let screenPoint = NSEvent.mouseLocation
            if !panel.frame.contains(screenPoint) {
                // Ignore clicks on the status item button itself (toggle handles that).
                if let button = self.statusItem?.button,
                   let buttonWindow = button.window {
                    let buttonRect = button.convert(button.bounds, to: nil)
                    let screenRect = buttonWindow.convertToScreen(buttonRect)
                    if screenRect.contains(screenPoint) { return }
                }
                Task { @MainActor in
                    self.hidePanel()
                }
            }
        }
    }

    private func removeDismissalMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePanel()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        // Belt-and-suspenders: never let close tear down residency.
        removeDismissalMonitors()
    }
}

/// Borderless panels return `false` from `canBecomeKey`, so `makeKeyAndOrderFront`
/// and `makeFirstResponder` are no-ops and every keystroke falls through. The
/// floating shelf must be keyable for search, arrow navigation, and Escape.
final class ClipboardShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
