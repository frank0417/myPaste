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
    @State private var recordingToken: Int?

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
                    .frame(minWidth: 84)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isRecording ? PasteTheme.accent.opacity(0.18) : Color.primary.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isRecording ? PasteTheme.accent : Color.primary.opacity(0.15), lineWidth: 1)
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

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        recordingToken = HotKeyRecordingSession.shared.begin { stopRecording() }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            guard !event.isARepeat else { return nil }
            // Esc cancels without changing the shortcut.
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let carbon = Self.carbonModifiers(from: event.modifierFlags)
            let candidate = HotKeyShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
            // Keep listening while only modifiers are down so the user can finish the combo.
            guard candidate.isComplete else { return nil }
            // Restores the other shortcut first, so duplicates are detected on apply.
            stopRecording()
            // Reserved, duplicate, or already-taken combos are reported by the caller.
            onChange(candidate)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let recordingToken {
            self.recordingToken = nil
            HotKeyRecordingSession.shared.end(recordingToken)
        }
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

    private var nextToken = 1
    private var activeToken: Int?
    private var cancelActive: (() -> Void)?

    func begin(cancel: @escaping () -> Void) -> Int {
        if let previous = cancelActive {
            cancelActive = nil
            activeToken = nil
            previous()
        }
        let token = nextToken
        nextToken += 1
        activeToken = token
        cancelActive = cancel
        GlobalHotKeyManager.shared.suspend()
        return token
    }

    func end(_ token: Int) {
        guard activeToken == token else { return }
        activeToken = nil
        cancelActive = nil
        GlobalHotKeyManager.shared.resume()
    }
}
