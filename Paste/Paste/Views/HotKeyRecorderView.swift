import SwiftUI
import AppKit
import Carbon.HIToolbox

/// A button that captures the next key press as the global panel shortcut.
struct HotKeyRecorderView: View {
    @Binding var shortcut: HotKeyShortcut
    var onChange: (HotKeyShortcut) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            startRecording()
        } label: {
            Text(isRecording ? "按下新快捷键…" : shortcut.display)
                .font(.system(size: 12, weight: .semibold).monospaced())
                .frame(minWidth: 72)
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
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc cancels without changing the shortcut.
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let carbon = Self.carbonModifiers(from: event.modifierFlags)
            guard carbon != 0 else { return nil } // require at least one modifier
            let new = HotKeyShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
            shortcut = new
            onChange(new)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
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
