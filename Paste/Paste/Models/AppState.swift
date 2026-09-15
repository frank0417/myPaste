import Foundation
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var searchQuery: String = ""
    @Published var selectedFilter: ContentFilter = .all
    @Published var selectedItemID: UUID?
    @Published var isMonitoringEnabled: Bool = true
    @Published var launchAtLogin: Bool = false
    @Published var maxHistoryCount: Int = 500
    @Published var syncEnabled: Bool = true
    @Published var showOnlyPinned: Bool = false
    @Published var requestClearHistory: Bool = false
    @Published var requestPinSelected: Bool = false
    @Published var hotkey: HotKeyShortcut = .default
    /// Result of the last hotkey change, shown in Settings.
    @Published var hotkeyFeedback: HotKeyFeedback?
    @Published var requestExportJSON: Bool = false
    /// When set, the shelf panel shows a full-content detail overlay for this item.
    @Published var shelfDetailItemID: UUID?
    /// Filter by automatic content tag (图片 / 链接 / 富文本 …).
    @Published var selectedAutoTag: String?
    @Published var panelViewMode: PanelViewMode = .shelf
    @Published var mainHistoryMode: MainHistoryMode = .list

    enum PanelViewMode: String {
        case shelf
        case timeline
    }

    enum MainHistoryMode: String {
        case list
        case timeline
    }

    enum ContentFilter: String, CaseIterable, Identifiable {
        case all
        case text
        case link
        case image
        case file
        case code
        case richText
        case color
        case snippet
        case pinned

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "全部"
            case .text: return "文本"
            case .link: return "链接"
            case .image: return "图片"
            case .file: return "文件"
            case .code: return "代码"
            case .richText: return "富文本"
            case .color: return "颜色"
            case .snippet: return "长文本"
            case .pinned: return "置顶"
            }
        }

        var systemImage: String {
            switch self {
            case .all: return "square.stack.3d.up"
            case .text: return "text.alignleft"
            case .link: return "link"
            case .image: return "photo"
            case .file: return "doc"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .richText: return "doc.richtext"
            case .color: return "paintpalette"
            case .snippet: return "text.quote"
            case .pinned: return "pin.fill"
            }
        }
    }

    var hotkeyDisplay: String { hotkey.display }

    init() {
        loadPreferences()
    }

    func loadPreferences() {
        let defaults = UserDefaults.standard
        isMonitoringEnabled = defaults.object(forKey: "isMonitoringEnabled") as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        maxHistoryCount = defaults.object(forKey: "maxHistoryCount") as? Int ?? 500
        syncEnabled = defaults.object(forKey: "syncEnabled") as? Bool ?? true
        hotkey = HotKeyShortcut.load()
    }

    func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(isMonitoringEnabled, forKey: "isMonitoringEnabled")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(maxHistoryCount, forKey: "maxHistoryCount")
        defaults.set(syncEnabled, forKey: "syncEnabled")
        hotkey.save()
    }

    /// Only persists the shortcut once it is actually registered with the system.
    @discardableResult
    func updateHotkey(_ shortcut: HotKeyShortcut) -> Bool {
        if shortcut == hotkey, GlobalHotKeyManager.shared.current == shortcut {
            hotkeyFeedback = .applied(shortcut.display)
            return true
        }
        switch GlobalHotKeyManager.shared.apply(shortcut) {
        case .applied:
            hotkey = shortcut
            shortcut.save()
            hotkeyFeedback = .applied(shortcut.display)
            StatusItemController.shared.refreshHotkeyHint(shortcut.display)
            return true
        case .rejected(let reason):
            hotkeyFeedback = .rejected(reason)
            return false
        }
    }

    /// Registers the stored shortcut at launch, falling back to the default if it is taken.
    func registerStoredHotkey() {
        let stored = HotKeyShortcut.load()
        if GlobalHotKeyManager.shared.current == stored {
            hotkey = stored
            return
        }
        if case .applied = GlobalHotKeyManager.shared.apply(stored) {
            hotkey = stored
            return
        }
        if case .applied = GlobalHotKeyManager.shared.apply(.default) {
            hotkey = .default
            HotKeyShortcut.default.save()
            if stored != .default {
                hotkeyFeedback = .rejected("原快捷键 \(stored.display) 已被占用，已恢复为 \(HotKeyShortcut.default.display)")
            }
        }
    }
}

enum HotKeyFeedback: Equatable {
    case applied(String)
    case rejected(String)

    var message: String {
        switch self {
        case .applied(let display): return "已生效：\(display)"
        case .rejected(let reason): return reason
        }
    }

    var isError: Bool {
        if case .rejected = self { return true }
        return false
    }
}


extension Notification.Name {
    static let pasteMonitoringPreferenceChanged = Notification.Name("pasteMonitoringPreferenceChanged")
}
