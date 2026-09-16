import AppKit
import SwiftUI

/// A brief, non-interactive toast confirming a capture.
///
/// Deliberately never activates the app and ignores mouse events: after a hotkey
/// capture the user is about to press ⌘V in whatever app they were using, so
/// stealing focus would paste into the wrong place.
@MainActor
final class ScreenshotHUD {
    static let shared = ScreenshotHUD()

    private static let visibleDuration: TimeInterval = 1.9
    private static let size = NSSize(width: 320, height: 64)

    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    private init() {}

    func show(thumbnail: NSImage?, title: String, detail: String) {
        let panel = panel ?? makePanel()
        self.panel = panel

        panel.contentView = NSHostingView(
            rootView: ScreenshotHUDView(thumbnail: thumbnail, title: title, detail: detail)
                .frame(width: Self.size.width, height: Self.size.height)
        )
        position(panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        dismissWork?.cancel()
        // Strong, immutable capture: the singleton outlives the timer anyway, and a
        // weak capture cannot be read from inside the nested main-actor closure.
        let work = DispatchWorkItem { [self] in
            MainActor.assumeIsolated {
                dismiss()
            }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: work)
    }

    private func dismiss() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Above the shelf and full-screen apps, but never focusable.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            panel.center()
            return
        }
        panel.setFrame(
            NSRect(
                x: visible.midX - Self.size.width / 2,
                y: visible.maxY - Self.size.height - 16,
                width: Self.size.width,
                height: Self.size.height
            ),
            display: false
        )
    }
}

/// The strip that appears under the pointer the moment a capture lands: the two
/// things people do next — read the text out of it, or save the file — plus close.
///
/// Non-activating, so ⌘V still goes to the app the user was in; but unlike the
/// toast it takes clicks. It lingers longer and stays while hovered.
@MainActor
final class ScreenshotActionBar {
    static let shared = ScreenshotActionBar()

    struct Actions {
        var recognizeText: @MainActor () -> Void
        var save: @MainActor () -> Void
    }

    private static let visibleDuration: TimeInterval = 7
    private static let size = NSSize(width: 372, height: 58)

    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    private init() {}

    /// `anchor` is the screen point the bar hangs below — the pointer, which after an
    /// interactive capture sits at the corner where the selection ended.
    func show(thumbnail: NSImage?, title: String, anchor: NSPoint, actions: Actions) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let model = ScreenshotActionBarModel(
            thumbnail: thumbnail,
            title: title,
            onRecognize: { [weak self] in
                self?.dismiss()
                actions.recognizeText()
            },
            onSave: { [weak self] in
                self?.dismiss()
                actions.save()
            },
            onClose: { [weak self] in self?.dismiss() },
            onHoverChange: { [weak self] hovering in
                if hovering {
                    self?.dismissWork?.cancel()
                } else {
                    self?.scheduleDismiss()
                }
            }
        )
        panel.contentView = NSHostingView(
            rootView: ScreenshotActionBarView(model: model)
                .frame(width: Self.size.width, height: Self.size.height)
        )
        position(panel, below: anchor)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        scheduleDismiss()
    }

    func dismiss() {
        dismissWork?.cancel()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func scheduleDismiss() {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [self] in
            MainActor.assumeIsolated {
                dismiss()
            }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: work)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        return panel
    }

    /// Centered on the anchor, hanging just below it, and kept on screen.
    private func position(_ panel: NSPanel, below anchor: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            panel.center()
            return
        }
        var x = anchor.x - Self.size.width / 2
        var y = anchor.y - Self.size.height - 14
        x = min(max(x, visible.minX + 8), visible.maxX - Self.size.width - 8)
        if y < visible.minY + 8 {
            // No room below: sit above the anchor instead.
            y = min(anchor.y + 14, visible.maxY - Self.size.height - 8)
        }
        panel.setFrame(NSRect(x: x, y: y, width: Self.size.width, height: Self.size.height), display: false)
    }
}

private struct ScreenshotActionBarModel {
    let thumbnail: NSImage?
    let title: String
    let onRecognize: () -> Void
    let onSave: () -> Void
    let onClose: () -> Void
    let onHoverChange: (Bool) -> Void
}

private struct ScreenshotActionBarView: View {
    let model: ScreenshotActionBarModel

    var body: some View {
        HStack(spacing: 10) {
            if let thumbnail = model.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(PasteTheme.accent)
                    .frame(width: 36, height: 36)
            }

            Text(model.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(minWidth: 0)

            Spacer(minLength: 6)

            actionButton("识别文字", systemImage: "text.viewfinder", action: model.onRecognize)
            actionButton("下载截图", systemImage: "arrow.down.to.line", action: model.onSave)

            Button(action: model.onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(PasteTheme.panelFill.opacity(0.9))
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .padding(4)
        .onHover(perform: model.onHoverChange)
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.06), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct ScreenshotHUDView: View {
    let thumbnail: NSImage?
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(PasteTheme.accent)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(PasteTheme.panelFill.opacity(0.94))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .padding(4)
    }
}
