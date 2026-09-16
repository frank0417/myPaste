import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox

/// A button that captures the next key press as a global shortcut.
struct HotKeyRecorderView: View {
    let action: HotKeyAction
    @Binding var shortcut: HotKeyShortcut
    var onChange: (HotKeyShortcut) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            } label: {
                Text(isRecording ? "按下新快捷键…" : shortcut.display)
                    .font(.system(size: 12, weight: .semibold).monospaced())
                    .foregroundStyle(PasteTheme.ink)
                    .frame(minWidth: 84)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(isRecording ? PasteTheme.accent.opacity(0.16) : Color(nsColor: .windowBackgroundColor).opacity(0.9))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isRecording ? PasteTheme.accent : Color.primary.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            }
            .buttonStyle(.plain)

            if shortcut != action.defaultShortcut {
                Button("恢复默认") {
                    stopRecording()
                    onChange(action.defaultShortcut)
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
        .onDisappear { stopRecording() }
        // Switching apps mid-recording would leave the hotkeys suspended.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            stopRecording()
        }
    }

    @MainActor
    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        HotKeyRecordingSession.shared.begin(action) { stopRecording() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags
            let repeated = event.isARepeat
            // Local monitors always fire on the main thread.
            MainActor.assumeIsolated {
                guard !repeated else { return }
                // Esc cancels without changing the shortcut.
                if keyCode == UInt16(kVK_Escape) {
                    stopRecording()
                    return
                }
                let candidate = HotKeyShortcut(
                    keyCode: UInt32(keyCode),
                    carbonModifiers: Self.carbonModifiers(from: flags)
                )
                // Keep listening while only modifiers are down so the user can finish the combo.
                guard candidate.isComplete else { return }
                // Restores the other shortcut first, so duplicates are detected on apply.
                stopRecording()
                // Reserved, duplicate, or already-taken combos are reported by the caller.
                onChange(candidate)
            }
            // Swallow every keystroke while recording so nothing else reacts to it.
            return nil
        }
    }

    @MainActor
    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        HotKeyRecordingSession.shared.end(action)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }
}

/// Settings shows one recorder per shortcut, but only one may listen at a time —
/// otherwise both rows would capture the same keystroke.
@MainActor
private final class HotKeyRecordingSession {
    static let shared = HotKeyRecordingSession()

    private var activeAction: HotKeyAction?
    private var cancelActive: (() -> Void)?

    func begin(_ action: HotKeyAction, cancel: @escaping () -> Void) {
        if let previous = cancelActive {
            activeAction = nil
            cancelActive = nil
            previous()
        }
        activeAction = action
        cancelActive = cancel
        GlobalHotKeyManager.shared.suspend()
    }

    func end(_ action: HotKeyAction) {
        guard activeAction == action else { return }
        activeAction = nil
        cancelActive = nil
        GlobalHotKeyManager.shared.resume()
    }
}
