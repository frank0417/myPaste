import ApplicationServices
import AppKit

/// Helper for macOS Accessibility (needed to synthesize ⌘V into other apps).
enum AccessibilityPermission {
    /// Returns whether this process is trusted for Accessibility APIs.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt / opens Privacy settings so Paste appears in the list.
    /// Unsigned apps only show up after this is called (or after posting CGEvents).
    @discardableResult
    static func requestIfNeeded(prompt: Bool = true) -> Bool {
        if AXIsProcessTrusted() { return true }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
}
