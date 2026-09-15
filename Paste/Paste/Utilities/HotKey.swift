import AppKit
import Carbon.HIToolbox

/// A user-configurable global keyboard shortcut (key code + Carbon modifiers).
struct HotKeyShortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_V),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    static let storageKey = "globalHotKeyShortcut"

    static func load() -> HotKeyShortcut {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let shortcut = try? JSONDecoder().decode(HotKeyShortcut.self, from: data),
              shortcut.rejectionReason == nil else {
            return .default
        }
        return shortcut
    }

    /// Modifier-only presses can't be a shortcut on their own.
    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
        kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
        kVK_CapsLock, kVK_Function
    ]

    /// Combos macOS or ClipStack itself owns; registering them would silently never fire
    /// or break a core action, so reject them while recording instead.
    private static let reserved: [(keyCode: Int, carbon: UInt32, name: String)] = [
        (kVK_Space, UInt32(cmdKey), "⌘Space（聚焦搜索）"),
        (kVK_Tab, UInt32(cmdKey), "⌘⇥（切换 App）"),
        (kVK_ANSI_Q, UInt32(cmdKey), "⌘Q（退出 App）"),
        (kVK_ANSI_3, UInt32(cmdKey | shiftKey), "⇧⌘3（截屏）"),
        (kVK_ANSI_4, UInt32(cmdKey | shiftKey), "⇧⌘4（截屏）"),
        (kVK_ANSI_5, UInt32(cmdKey | shiftKey), "⇧⌘5（截屏）")
    ]

    /// False while the user is still holding modifiers, so the recorder can keep listening.
    /// Shift alone doesn't count: ⇧ + letter is just typing.
    var isComplete: Bool {
        guard !Self.modifierKeyCodes.contains(Int(keyCode)) else { return false }
        let meaningful = UInt32(cmdKey) | UInt32(controlKey) | UInt32(optionKey)
        return carbonModifiers & meaningful != 0
    }

    /// `nil` when the combo is usable as a global shortcut.
    var rejectionReason: String? {
        if Self.modifierKeyCodes.contains(Int(keyCode)) {
            return "请在按住修饰键的同时按一个字母、数字或功能键"
        }
        guard isComplete else {
            return "快捷键需要包含 ⌘ / ⌃ / ⌥ 中的至少一个"
        }
        if let match = Self.reserved.first(where: { $0.keyCode == Int(keyCode) && $0.carbon == carbonModifiers }) {
            return "\(match.name) 已被系统占用，请换一个组合"
        }
        return nil
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Cocoa event modifiers equivalent to the stored Carbon modifiers.
    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    var display: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += Self.keyName(for: keyCode)
        return s
    }

    static func keyName(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            break
        }
        // Translate the virtual key code to the character it produces.
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataRef).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status: OSStatus = layoutData.withUnsafeBytes { ptr -> OSStatus in
            guard let base = ptr.baseAddress else { return OSStatus(errAEBadListItem) }
            return UCKeyTranslate(
                base.assumingMemoryBound(to: UCKeyboardLayout.self),
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }
        guard status == noErr, length > 0 else { return "?" }
        let name = String(utf16CodeUnits: chars, count: length)
        return name.uppercased()
    }
}

enum HotKeyApplyResult: Equatable {
    case applied
    case rejected(String)
}

/// Registers a global hotkey to reveal the ClipStack menu-bar panel / main window.
@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var suspendedShortcut: HotKeyShortcut?
    var onHotKey: (() -> Void)?
    private(set) var current: HotKeyShortcut?

    private init() {}

    /// Validates, registers, and keeps the previous binding when the new combo is unusable.
    @discardableResult
    func apply(_ shortcut: HotKeyShortcut) -> HotKeyApplyResult {
        if let reason = shortcut.rejectionReason {
            return .rejected(reason)
        }
        guard installHandlerIfNeeded() else {
            return .rejected("无法注册全局快捷键，请重启 ClipStack 后重试")
        }

        let previous = current
        unregisterHotKey()
        if bind(shortcut) {
            current = shortcut
            return .applied
        }

        // A failed registration must not leave the app without any hotkey.
        if let previous, bind(previous) {
            current = previous
        }
        return .rejected("该组合已被其他 App 占用，请换一个")
    }

    /// Stops the live hotkey from swallowing keystrokes while the user records a new one.
    func suspend() {
        guard suspendedShortcut == nil, let current else { return }
        suspendedShortcut = current
        unregisterHotKey()
    }

    func resume() {
        guard let shortcut = suspendedShortcut else { return }
        suspendedShortcut = nil
        if hotKeyRef == nil, bind(shortcut) {
            current = shortcut
        }
    }

    func unregister() {
        unregisterHotKey()
        suspendedShortcut = nil
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    private func bind(_ shortcut: HotKeyShortcut) -> Bool {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4353544B), id: 1) // 'CSTK'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return false }
        hotKeyRef = ref
        return true
    }

    private func unregisterHotKey() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    /// The Carbon handler outlives individual bindings, so install it only once.
    private func installHandlerIfNeeded() -> Bool {
        if handlerRef != nil { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.onHotKey?()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        return status == noErr
    }
}
