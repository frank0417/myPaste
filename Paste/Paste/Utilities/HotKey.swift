import AppKit
import Carbon.HIToolbox

/// Everything a global shortcut can trigger. The two window surfaces are mutually
/// exclusive: showing one always hides the other. Screenshots need no window at all;
/// text recognition is something the user picks on a capture, not a separate key.
enum HotKeyAction: String, CaseIterable, Identifiable {
    case panel
    case mainWindow
    case screenshot

    var id: String { rawValue }

    /// Settings row label.
    var title: String {
        switch self {
        case .panel: return "唤出剪贴板面板"
        case .mainWindow: return "唤出主窗口"
        case .screenshot: return "截图（区域）"
        }
    }

    /// Used inside conflict messages.
    var shortTitle: String {
        switch self {
        case .panel: return "剪贴板面板"
        case .mainWindow: return "主窗口"
        case .screenshot: return "截图"
        }
    }

    var storageKey: String {
        switch self {
        // Unchanged so shortcuts saved by earlier versions keep working.
        case .panel: return "globalHotKeyShortcut"
        case .mainWindow: return "mainWindowHotKeyShortcut"
        case .screenshot: return "screenshotHotKeyShortcut"
        }
    }

    var defaultShortcut: HotKeyShortcut {
        switch self {
        case .panel:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | shiftKey))
        case .mainWindow:
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_V), carbonModifiers: UInt32(cmdKey | optionKey))
        case .screenshot:
            // ⇧⌘X — ⇧⌘D was the previous factory default (migrated on load).
            return HotKeyShortcut(keyCode: UInt32(kVK_ANSI_X), carbonModifiers: UInt32(cmdKey | shiftKey))
        }
    }

    fileprivate var hotKeyID: UInt32 {
        switch self {
        case .panel: return 1
        case .mainWindow: return 2
        case .screenshot: return 3
        }
    }
}

/// A user-configurable global keyboard shortcut (key code + Carbon modifiers).
struct HotKeyShortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static func load(_ action: HotKeyAction) -> HotKeyShortcut {
        guard let data = UserDefaults.standard.data(forKey: action.storageKey),
              let shortcut = try? JSONDecoder().decode(HotKeyShortcut.self, from: data),
              shortcut.rejectionReason == nil else {
            return action.defaultShortcut
        }
        // ⇧⌘D was the factory screenshot combo. Treat a still-stored copy as
        // unset so existing installs pick up ⇧⌘X; a combo the user recorded
        // themselves is left alone.
        if action == .screenshot, shortcut == Self.retiredScreenshotDefault {
            return action.defaultShortcut
        }
        return shortcut
    }

    /// Factory screenshot combo before ⇧⌘X.
    private static let retiredScreenshotDefault = HotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    func save(for action: HotKeyAction) {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: action.storageKey)
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

    /// Modifier-only presses can't be a shortcut on their own.
    private static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
        kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
        kVK_CapsLock, kVK_Function
    ]

    /// Combos macOS or PasteNest itself owns; registering them would silently never fire
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

/// Registers the global hotkeys that reveal the PasteNest shelf and main window.
@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    private struct Binding {
        let ref: EventHotKeyRef
        let shortcut: HotKeyShortcut
    }

    private var bindings: [HotKeyAction: Binding] = [:]
    private var suspended: [HotKeyAction: HotKeyShortcut] = [:]
    private var handlerRef: EventHandlerRef?
    var onHotKey: ((HotKeyAction) -> Void)?

    private init() {}

    /// The combo currently live with the system, or `nil` when the action has no binding.
    func shortcut(for action: HotKeyAction) -> HotKeyShortcut? {
        bindings[action]?.shortcut
    }

    /// Validates, registers, and keeps the previous binding when the new combo is unusable.
    @discardableResult
    func apply(_ shortcut: HotKeyShortcut, for action: HotKeyAction) -> HotKeyApplyResult {
        if let reason = shortcut.rejectionReason {
            return .rejected(reason)
        }
        if let clash = bindings.first(where: { $0.key != action && $0.value.shortcut == shortcut }) {
            return .rejected("与「\(clash.key.shortTitle)」快捷键相同，请换一个")
        }
        guard installHandlerIfNeeded() else {
            return .rejected("无法注册全局快捷键，请重启 PasteNest 后重试")
        }

        let previous = bindings[action]?.shortcut
        unbind(action)
        if bind(shortcut, for: action) {
            return .applied
        }

        // A failed registration must not leave the action without any hotkey.
        if let previous {
            _ = bind(previous, for: action)
        }
        return .rejected("该组合已被其他 App 占用，请换一个")
    }

    /// Stops the live hotkeys from swallowing keystrokes while the user records a new one.
    func suspend() {
        guard suspended.isEmpty else { return }
        for (action, binding) in bindings {
            suspended[action] = binding.shortcut
        }
        for action in suspended.keys {
            unbind(action)
        }
    }

    func resume() {
        let pending = suspended
        suspended = [:]
        for (action, shortcut) in pending where bindings[action] == nil {
            _ = bind(shortcut, for: action)
        }
    }

    func unregister() {
        for action in Array(bindings.keys) {
            unbind(action)
        }
        suspended = [:]
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    fileprivate func dispatch(_ hotKeyID: UInt32) {
        guard let action = HotKeyAction.allCases.first(where: { $0.hotKeyID == hotKeyID }) else { return }
        onHotKey?(action)
    }

    private func bind(_ shortcut: HotKeyShortcut, for action: HotKeyAction) -> Bool {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4353544B), id: action.hotKeyID) // 'CSTK'
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
        bindings[action] = Binding(ref: ref, shortcut: shortcut)
        return true
    }

    private func unbind(_ action: HotKeyAction) {
        guard let binding = bindings.removeValue(forKey: action) else { return }
        UnregisterEventHotKey(binding.ref)
    }

    /// The Carbon handler outlives individual bindings, so install it only once.
    private func installHandlerIfNeeded() -> Bool {
        if handlerRef != nil { return true }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, userData) -> OSStatus in
                guard let event, let userData else { return noErr }
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    .init(MemoryLayout<EventHotKeyID>.size),
                    nil,
                    &pressed
                )
                guard status == noErr else { return noErr }
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = pressed.id
                Task { @MainActor in
                    manager.dispatch(id)
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
