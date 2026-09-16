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
    /// How long a record that nobody favorited survives. Favorites are kept forever.
    @Published var keepUnfavoritedDays: Int = RetentionPolicy.defaultDays
    @Published var syncEnabled: Bool = true
    @Published var showOnlyPinned: Bool = false
    /// Set by the favorites folder surfaces; cleared when they switch away.
    @Published var showOnlyFavorites: Bool = false
    /// Which category chip is active inside the favorites folder.
    @Published var favoriteScope: FavoriteScope = .all
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
    /// Which Settings tab is showing; menus set it so "快捷键设置…" lands on that tab.
    @Published var settingsTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general
        case hotkeys
        case history
        case sync
        case about
    }

    enum PanelViewMode: String {
        case shelf
        case timeline
        case favorites
    }
    enum MainHistoryMode: String {
        case list
        case timeline
        case favorites
    }

    /// True on every surface that shows the favorites folder instead of the history.
    var favoritesOnly: Bool {
        selectedFilter == .favorite || showOnlyFavorites
    }

    /// Enters the folder, or moves to another category inside it.
    func showFavorites(scope: FavoriteScope = .all) {
        showOnlyFavorites = true
        favoriteScope = scope
        selectedAutoTag = nil
        showOnlyPinned = false
        if selectedFilter != .favorite {
            selectedFilter = .all
        }
    }

    /// Leaves the folder. Every history surface calls this so the favorites-only
    /// filter can never linger on a view that has no category chips.
    func leaveFavorites() {
        showOnlyFavorites = false
        favoriteScope = .all
        if selectedFilter == .favorite {
            selectedFilter = .all
        }
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
        case favorite

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
            case .favorite: return "收藏夹"
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
            case .favorite: return "star.fill"
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
        keepUnfavoritedDays = RetentionPolicy.clampDays(
            defaults.object(forKey: "keepUnfavoritedDays") as? Int ?? RetentionPolicy.defaultDays
        )
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
        defaults.set(keepUnfavoritedDays, forKey: "keepUnfavoritedDays")
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

    /// The combo the system is actually listening for right now, or `nil` if the
    /// action has no live binding. Settings shows this next to each recorder so the
    /// user sees what took effect, not just what was typed.
    func liveShortcut(for action: HotKeyAction) -> HotKeyShortcut? {
        GlobalHotKeyManager.shared.shortcut(for: action)
    }

    /// Puts every shortcut back to its default and registers each one right away.
    func resetHotkeysToDefaults() {
        for action in HotKeyAction.allCases {
            updateHotkey(action.defaultShortcut, for: action)
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
    /// Asks the store that owns monitoring to apply the retention policy right away.
    static let pasteRetentionSweepRequested = Notification.Name("pasteRetentionSweepRequested")
}
