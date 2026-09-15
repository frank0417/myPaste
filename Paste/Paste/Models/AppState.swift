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
    /// Reveals the bottom shelf panel.
    @Published var hotkey: HotKeyShortcut = HotKeyAction.panel.defaultShortcut
    /// Reveals the main window.
    @Published var mainWindowHotkey: HotKeyShortcut = HotKeyAction.mainWindow.defaultShortcut
    /// Starts an interactive region screenshot.
    @Published var screenshotHotkey: HotKeyShortcut = HotKeyAction.screenshot.defaultShortcut
    /// Result of the last change per shortcut, shown in Settings.
    @Published var hotkeyFeedback: [HotKeyAction: HotKeyFeedback] = [:]
    @Published var requestExportJSON: Bool = false
    /// When set, the shelf panel shows a full-content detail overlay for this item.
    @Published var shelfDetailItemID: UUID?
    /// The shelf panel's standalone search field, floating above its nav bar.
    /// Owned by AppState so the panel controller can close it from its key monitor.
    @Published var isPanelSearchVisible: Bool = false
    /// Filter by automatic content tag (图片 / 链接 / 富文本 …).
    @Published var selectedAutoTag: String?
    /// Bumped when on-device embeddings finish a batch so search results can refresh.
    @Published var embeddingRevision: Int = 0
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
    var mainWindowHotkeyDisplay: String { mainWindowHotkey.display }
    var screenshotHotkeyDisplay: String { screenshotHotkey.display }

    func shortcut(for action: HotKeyAction) -> HotKeyShortcut {
        switch action {
        case .panel: return hotkey
        case .mainWindow: return mainWindowHotkey
        case .screenshot: return screenshotHotkey
        }
    }

    init() {
        loadPreferences()
    }

    func loadPreferences() {
        let defaults = UserDefaults.standard
        isMonitoringEnabled = defaults.object(forKey: "isMonitoringEnabled") as? Bool ?? true
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        maxHistoryCount = defaults.object(forKey: "maxHistoryCount") as? Int ?? 500
        syncEnabled = defaults.object(forKey: "syncEnabled") as? Bool ?? true
        hotkey = HotKeyShortcut.load(.panel)
        mainWindowHotkey = HotKeyShortcut.load(.mainWindow)
        screenshotHotkey = HotKeyShortcut.load(.screenshot)
    }

    func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(isMonitoringEnabled, forKey: "isMonitoringEnabled")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(maxHistoryCount, forKey: "maxHistoryCount")
        defaults.set(syncEnabled, forKey: "syncEnabled")
        hotkey.save(for: .panel)
        mainWindowHotkey.save(for: .mainWindow)
        screenshotHotkey.save(for: .screenshot)
    }

    /// Only persists the shortcut once it is actually registered with the system.
    @discardableResult
    func updateHotkey(_ shortcut: HotKeyShortcut, for action: HotKeyAction) -> Bool {
        if shortcut == self.shortcut(for: action), GlobalHotKeyManager.shared.shortcut(for: action) == shortcut {
            hotkeyFeedback[action] = .applied(shortcut.display)
            return true
        }
        switch GlobalHotKeyManager.shared.apply(shortcut, for: action) {
        case .applied:
            store(shortcut, for: action)
            hotkeyFeedback[action] = .applied(shortcut.display)
            return true
        case .rejected(let reason):
            hotkeyFeedback[action] = .rejected(reason)
            return false
        }
    }

    /// Registers the stored shortcuts at launch, falling back to the defaults if taken.
    func registerStoredHotkeys() {
        for action in HotKeyAction.allCases {
            registerStoredHotkey(action)
        }
    }

    private func registerStoredHotkey(_ action: HotKeyAction) {
        let stored = HotKeyShortcut.load(action)
        if GlobalHotKeyManager.shared.shortcut(for: action) == stored {
            store(stored, for: action, persist: false)
            return
        }
        if case .applied = GlobalHotKeyManager.shared.apply(stored, for: action) {
            store(stored, for: action, persist: false)
            return
        }

        let fallback = action.defaultShortcut
        if stored != fallback, case .applied = GlobalHotKeyManager.shared.apply(fallback, for: action) {
            store(fallback, for: action)
            hotkeyFeedback[action] = .rejected("原快捷键 \(stored.display) 已被占用，已恢复为 \(fallback.display)")
            return
        }
        hotkeyFeedback[action] = .rejected("\(stored.display) 已被占用，请设置一个新组合")
    }

    private func store(_ shortcut: HotKeyShortcut, for action: HotKeyAction, persist: Bool = true) {
        switch action {
        case .panel:
            hotkey = shortcut
            StatusItemController.shared.refreshHotkeyHint(shortcut.display)
        case .mainWindow:
            mainWindowHotkey = shortcut
        case .screenshot:
            screenshotHotkey = shortcut
        }
        if persist {
            shortcut.save(for: action)
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
