import AppKit
import SwiftUI
import SwiftData

/// AppKit status-item + floating panel. More reliable than MenuBarExtra for
/// showing a clipboard panel from a global hotkey.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var modelContainer: ModelContainer?
    private var appState: AppState?

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
                button.toolTip = "Paste — 剪贴板历史（⇧⌘V）"
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
        togglePanel()
    }

    func togglePanel() {
        guard let panel else {
            showPanel()
            return
        }
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let panel, let button = statusItem?.button else { return }

        // Refresh hosting root in case environment objects changed.
        if let container = modelContainer, let appState {
            let root = MenuBarPanel()
                .environmentObject(appState)
                .modelContainer(container)
                .frame(width: 420, height: 560)
            panel.contentView = NSHostingView(rootView: root)
        }

        positionPanel(panel, relativeTo: button)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Paste"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self

        if let container = modelContainer, let appState {
            let root = MenuBarPanel()
                .environmentObject(appState)
                .modelContainer(container)
                .frame(width: 420, height: 560)
            panel.contentView = NSHostingView(rootView: root)
        }

        return panel
    }

    private func positionPanel(_ panel: NSPanel, relativeTo button: NSStatusBarButton) {
        guard let buttonWindow = button.window else {
            panel.center()
            return
        }
        let buttonRect = button.convert(button.bounds, to: nil)
        let screenRect = buttonWindow.convertToScreen(buttonRect)
        let panelSize = panel.frame.size
        var origin = NSPoint(
            x: screenRect.midX - panelSize.width / 2,
            y: screenRect.minY - panelSize.height - 8
        )

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panelSize.width - 8)
            if origin.y < visible.minY + 8 {
                origin.y = screenRect.maxY + 8
            }
        }
        panel.setFrameOrigin(origin)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Keep panel open when interacting with other apps is fine for clipboard use;
        // only auto-hide if user clicks away while it's a transient popover-like panel.
        // Disabled auto-hide so hotkey + click remain predictable.
    }
}
