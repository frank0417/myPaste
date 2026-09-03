import AppKit
import SwiftUI
import SwiftData
import QuartzCore

/// Menu-bar status item + bottom floating clipboard shelf.
/// Closing the panel only hides it — the app stays resident for ⇧⌘V.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    static let shared = StatusItemController()

    static let panelWidth: CGFloat = 980
    static let panelHeight: CGFloat = 390
    /// Tall enough for the detail overlay (header + body + footer) without clipping.
    static let detailPanelHeight: CGFloat = 600

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
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
                let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste")
                image?.isTemplate = true
                button.image = image
                button.toolTip = "Paste — 常驻后台（⇧⌘V 唤出）"
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
        menu.addItem(withTitle: "显示剪贴板", action: #selector(menuShowPanel), keyEquivalent: "")
        menu.addItem(withTitle: "隐藏面板", action: #selector(menuHidePanel), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "退出 Paste", action: #selector(menuQuit), keyEquivalent: "q")
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
    @objc private func menuHidePanel() { hidePanel() }
    @objc private func menuOpenSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
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

    func showPanel() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }

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
        isDetailExpanded = false
        panel?.orderOut(nil)
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
        let panel = NSPanel(
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
