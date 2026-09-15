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
