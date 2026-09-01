import AppKit
import Foundation

enum PasteHotKey {
    /// Default global hotkey display. Register via Carbon / KeyboardShortcuts when distributing.
    static let defaultDisplay = "⇧⌘V"
    static let openPanelKeyCode: UInt16 = 9 // ANSI V
    static let openPanelModifiers: UInt = UInt(
        NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.command.rawValue
    )
}
