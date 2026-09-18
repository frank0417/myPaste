import Foundation

/// Shelf chrome for the three languages PasteNest ships: Simplified Chinese
/// (default), Traditional Chinese, and English. Layout (type size, tracking,
/// chip scale) keys off `language` so longer English labels still fit.
enum PanelL10n {
    enum Language: String {
        case zhHans
        case zhHant
        case en
    }

    /// First matching preferred language; anything else falls back to zh-Hans.
    static var language: Language {
        for preferred in Locale.preferredLanguages {
            let lower = preferred.lowercased()
            if lower.hasPrefix("en") { return .en }
            if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw")
                || lower.hasPrefix("zh-hk") || lower.hasPrefix("zh-mo") {
                return .zhHant
            }
            if lower.hasPrefix("zh") { return .zhHans }
            let locale = Locale(identifier: preferred)
            if locale.language.languageCode?.identifier == "en" { return .en }
            if locale.language.languageCode?.identifier == "zh" {
                let script = locale.language.script?.identifier
                let region = locale.region?.identifier
                if script == "Hant" || region == "TW" || region == "HK" || region == "MO" {
                    return .zhHant
                }
                return .zhHans
            }
        }
        return .zhHans
    }

    static func pick(_ hans: String, hant: String, en: String) -> String {
        switch language {
        case .zhHant: return hant
        case .en: return en
        case .zhHans: return hans
        }
    }

    static var locale: Locale {
        switch language {
        case .zhHans: return Locale(identifier: "zh-Hans")
        case .zhHant: return Locale(identifier: "zh-Hant")
        case .en: return Locale(identifier: "en")
        }
    }

    static var clipboard: String { pick("剪贴板", hant: "剪貼板", en: "Board") }
    static var favorites: String { pick("收藏夹", hant: "收藏夾", en: "Saved") }
    static var timeline: String { pick("时间线", hant: "時間線", en: "Timeline") }
    static var search: String { pick("搜索", hant: "搜尋", en: "Search") }
    static var collapseSearch: String { pick("收起搜索", hant: "收起搜尋", en: "Hide search") }
    static var clearSearch: String { pick("清空", hant: "清空", en: "Clear") }
    static var searchPlaceholder: String { pick("搜索剪贴板…", hant: "搜尋剪貼板…", en: "Search…") }
    static var menu: String { pick("菜单", hant: "選單", en: "Menu") }
    static var listening: String { pick("后台监听中", hant: "背景監聽中", en: "Listening") }
    static var paused: String { pick("已暂停", hant: "已暫停", en: "Paused") }

    static func captureHelp(_ hotkey: String) -> String {
        pick(
            "截图（\(hotkey)）冻结屏幕并标注，结果存入历史",
            hant: "截圖（\(hotkey)）凍結螢幕並標註，結果存入歷史",
            en: "Capture (\(hotkey)) freezes the screen so you can annotate; the result goes into history"
        )
    }

    static var launchTitle: String { pick("登录时打开", hant: "登入時打開", en: "Open at login") }
    static var launchDetail: String {
        pick(
            "重启 Mac 后自动启动 PasteNest，保持常驻后台。",
            hant: "重啟 Mac 後自動啟動 PasteNest，保持常駐背景。",
            en: "Start PasteNest when you log in, so it stays in the menu bar."
        )
    }
    static var enable: String { pick("启用", hant: "啟用", en: "Enable") }
    static var backgroundTitle: String { pick("常驻后台", hant: "常駐背景", en: "Always on") }
    static func backgroundDetail(_ hotkey: String) -> String {
        pick(
            "关闭面板不会退出。按 \(hotkey) 随时唤出。",
            hant: "關閉面板不會結束。按 \(hotkey) 隨時喚出。",
            en: "Closing the panel does not quit. Press \(hotkey) to bring it back."
        )
    }
    static var gotIt: String { pick("知道了", hant: "知道了", en: "Got it") }

    static func emptySearchTitle(_ query: String) -> String {
        pick(
            "没有匹配「\(query)」的内容",
            hant: "沒有符合「\(query)」的內容",
            en: "No matches for “\(query)”"
        )
    }
    static var emptyTitle: String { pick("复制任意内容后会出现在这里", hant: "複製任何內容後會出現在這裡", en: "Copy anything and it will show up here") }
    static var emptySearchDetail: String { pick("换个关键词，或试试更口语的说法", hant: "換個關鍵詞，或試試更口語的說法", en: "Try another keyword, or a more casual phrasing") }
    static var emptyDetail: String { pick("面板可随时关闭，App 继续在菜单栏后台运行", hant: "面板可隨時關閉，App 繼續在選單列背景執行", en: "You can close the panel; the app keeps running in the menu bar") }

    static var favoritesEmpty: String { pick("收藏夹还是空的", hant: "收藏夾還是空的", en: "Nothing saved yet") }
    static var favoritesEmptySearch: String { pick("收藏夹里没有匹配的内容", hant: "收藏夾裡沒有符合的內容", en: "No matches in Saved") }
    static func favoritesEmptyTag(_ name: String) -> String {
        pick("「\(name)」分类下还没有内容", hant: "「\(name)」分類下還沒有內容", en: "Nothing in “\(name)” yet")
    }
    static var favoritesAllTagged: String { pick("所有收藏都已分类", hant: "所有收藏都已分類", en: "Every saved item has a tag") }
    static func favoritesEmptyDetail(_ days: Int) -> String {
        pick(
            "收藏的内容长期保存；未收藏的只保留 \(days) 天。右键任意卡片选择「收藏」即可放进来。",
            hant: "收藏的內容長期保存；未收藏的只保留 \(days) 天。對卡片按右鍵選擇「收藏」即可放進來。",
            en: "Saved items stay. Unsaved ones expire after \(days) days. Right-click a card and choose Save."
        )
    }
    static var favoritesEmptySearchDetail: String { pick("换个关键词，或切回「全部收藏」", hant: "換個關鍵詞，或切回「全部收藏」", en: "Try another keyword, or switch back to All saved") }
    static var favoritesUntaggedDetail: String { pick("右键收藏卡片 →「分类」可以随时调整标签。", hant: "對收藏卡片按右鍵 →「分類」可以隨時調整標籤。", en: "Right-click a saved card → Tag to change labels.") }
    static var favoritesTagDetail: String { pick("右键收藏卡片 →「分类」把内容打上这个标签。", hant: "對收藏卡片按右鍵 →「分類」把內容打上這個標籤。", en: "Right-click a saved card → Tag to apply this label.") }

    static var allFavorites: String { pick("全部收藏", hant: "全部收藏", en: "All saved") }
    static var untagged: String { pick("未分类", hant: "未分類", en: "Untagged") }
    static var tag: String { pick("分类", hant: "分類", en: "Tag") }
    static var newTagHelp: String { pick("新建分类并应用到选中的收藏", hant: "新建分類並套用到選中的收藏", en: "Create a tag and apply it to the selected item") }
    static var pickFavoriteFirst: String { pick("先选中一条收藏", hant: "先選中一則收藏", en: "Select a saved item first") }
    static var tagPlaceholder: String { pick("分类名称，回车确认", hant: "分類名稱，按 Return 確認", en: "Tag name, then Return") }
    static func deleteTag(_ name: String) -> String {
        pick("删除分类「\(name)」", hant: "刪除分類「\(name)」", en: "Delete tag “\(name)”")
    }

    static var all: String { pick("全部", hant: "全部", en: "All") }
    static var timelineEmpty: String { pick("时间线为空", hant: "時間線是空的", en: "Timeline is empty") }
    static var timelineEmptySearch: String { pick("没有字面或相近的记录", hant: "沒有字面或相近的記錄", en: "No literal or close matches") }
    static var timelineEmptyDetail: String { pick("复制内容后会按日期出现在这里", hant: "複製內容後會按日期出現在這裡", en: "Copied items show up here by date") }
    static var timelineEmptySearchDetail: String { pick("试试其他关键词、口语说法或切换标签", hant: "試試其他關鍵詞、口語說法或切換標籤", en: "Try another keyword, a casual phrasing, or a different tag") }
    static var today: String { pick("今天", hant: "今天", en: "Today") }
    static var yesterday: String { pick("昨天", hant: "昨天", en: "Yesterday") }

    static var details: String { pick("查看详情", hant: "查看詳細資料", en: "Details") }
    static var paste: String { pick("粘贴", hant: "貼上", en: "Paste") }
    static var copy: String { pick("复制", hant: "複製", en: "Copy") }
    static var cancel: String { pick("取消", hant: "取消", en: "Cancel") }
    static var copyText: String { pick("复制文字", hant: "複製文字", en: "Text") }
    static var copyRecognized: String { pick("复制识别的文字", hant: "複製辨識的文字", en: "Copy recognized text") }
    static var recognizeText: String { pick("识别文字", hant: "辨識文字", en: "Read") }
    static var recognizeHelp: String { pick("用 Vision 在本机识别这张截图里的文字", hant: "用 Vision 在本機辨識這張截圖裡的文字", en: "Recognize text in this screenshot on-device with Vision") }
    static var download: String { pick("下载", hant: "下載", en: "Save") }
    static var downloadImage: String { pick("下载图片", hant: "下載圖片", en: "Download image") }
    static var downloadHelp: String { pick("保存为 PNG 到「下载」", hant: "儲存為 PNG 到「下載」", en: "Save as PNG to Downloads") }
    static var favorite: String { pick("收藏（长期保存）", hant: "收藏（長期保存）", en: "Save (keep forever)") }
    static var favoriteHelp: String { pick("收藏，长期保存", hant: "收藏，長期保存", en: "Save, keep forever") }
    static var unfavorite: String { pick("从收藏夹移除", hant: "從收藏夾移除", en: "Remove from Saved") }
    static var pin: String { pick("置顶", hant: "置頂", en: "Pin") }
    static var unpin: String { pick("取消置顶", hant: "取消置頂", en: "Unpin") }
    static var delete: String { pick("删除", hant: "刪除", en: "Delete") }
    static var closeEsc: String { pick("关闭 (Esc)", hant: "關閉 (Esc)", en: "Close (Esc)") }
    static var recognizedHeading: String { pick("识别到的文字", hant: "辨識到的文字", en: "Recognized text") }
    static var imageUnavailable: String { pick("无法预览图片", hant: "無法預覽圖片", en: "Image can’t be previewed") }
    static var textBadge: String { pick("文字", hant: "文字", en: "Text") }

    static func characterCount(_ n: Int) -> String {
        pick("\(n) 个字符", hant: "\(n) 個字元", en: n == 1 ? "1 character" : "\(n) characters")
    }

    static func recognizedCount(_ n: Int) -> String {
        pick("\(n) 字", hant: "\(n) 字", en: n == 1 ? "1 char" : "\(n) chars")
    }

    static var expiringSoonHelp: String {
        pick(
            "未收藏，不到 1 天后自动清理",
            hant: "未收藏，不到 1 天後自動清理",
            en: "Not saved; auto-clears in less than a day"
        )
    }

    static func contentType(_ type: ClipboardContentType) -> String {
        switch type {
        case .text: return pick("文本", hant: "文字", en: "Text")
        case .richText: return pick("富文本", hant: "富文字", en: "Rich text")
        case .link: return pick("链接", hant: "連結", en: "Link")
        case .image: return pick("图片", hant: "圖片", en: "Image")
        case .color: return pick("颜色", hant: "顏色", en: "Color")
        case .file: return pick("文件", hant: "檔案", en: "File")
        case .code: return pick("代码", hant: "程式碼", en: "Code")
        case .snippet: return pick("片段", hant: "片段", en: "Snippet")
        }
    }

    static func autoTag(_ tag: AutoTag) -> String {
        switch tag {
        case .image: return pick("图片", hant: "圖片", en: "Image")
        case .link: return pick("链接", hant: "連結", en: "Link")
        case .richText: return pick("富文本", hant: "富文字", en: "Rich text")
        case .text: return pick("文本", hant: "文字", en: "Text")
        case .code: return pick("代码", hant: "程式碼", en: "Code")
        case .file: return pick("文件", hant: "檔案", en: "File")
        case .color: return pick("颜色", hant: "顏色", en: "Color")
        case .snippet: return pick("长文本", hant: "長文字", en: "Long text")
        }
    }

    static var keptFavorite: String { pick("已收藏 · 长期保存", hant: "已收藏 · 長期保存", en: "Saved · kept") }
    static var keptPinned: String { pick("已置顶 · 长期保存", hant: "已置頂 · 長期保存", en: "Pinned · kept") }
    static var expired: String { pick("已过期 · 即将自动清理", hant: "已過期 · 即將自動清理", en: "Expired · will be cleared") }
    static var expiresUnderOneDay: String {
        pick("不到 1 天后自动清理，收藏可长期保存", hant: "不到 1 天後自動清理，收藏可長期保存", en: "Clears in less than a day; save to keep")
    }
    static func expiresInDays(_ days: Int) -> String {
        pick(
            "\(days) 天后自动清理，收藏可长期保存",
            hant: "\(days) 天後自動清理，收藏可長期保存",
            en: days == 1 ? "Clears in 1 day; save to keep" : "Clears in \(days) days; save to keep"
        )
    }

    static var dayFormat: String {
        pick("yyyy年M月d日", hant: "yyyy年M月d日", en: "MMM d, yyyy")
    }

    // MARK: - Settings

    static var settings: String { pick("设置", hant: "設定", en: "Settings") }
    static var settingsEllipsis: String { pick("设置…", hant: "設定…", en: "Settings…") }
    static var openSettings: String { pick("打开设置…", hant: "打開設定…", en: "Open Settings…") }
    static var settingsTabGeneral: String { pick("通用", hant: "一般", en: "General") }
    static var settingsTabHotkeys: String { pick("快捷键", hant: "快捷鍵", en: "Hotkeys") }
    static var settingsTabHistory: String { pick("历史", hant: "歷史", en: "History") }
    static var settingsTabSync: String { pick("同步", hant: "同步", en: "Sync") }
    static var settingsTabAbout: String { pick("关于", hant: "關於", en: "About") }

    static var preferences: String { pick("偏好", hant: "偏好", en: "Preferences") }
    static var listenClipboard: String { pick("监听剪贴板", hant: "監聽剪貼板", en: "Watch clipboard") }
    static var listenClipboardCaption: String {
        pick(
            "复制后会按类型自动打标签（图片、链接、富文本等），可在时间线或标签栏筛选。",
            hant: "複製後會依類型自動打標籤（圖片、連結、富文字等），可在時間線或標籤列篩選。",
            en: "Copied items are tagged by type (images, links, rich text, and more) so you can filter the timeline."
        )
    }
    static var launchAtLogin: String { pick("登录时启动", hant: "登入時啟動", en: "Open at login") }
    static var launchAtLoginCaption: String {
        pick(
            "PasteNest 常驻菜单栏后台，关掉窗口不会退出。",
            hant: "PasteNest 常駐選單列背景，關掉視窗不會結束。",
            en: "PasteNest stays in the menu bar. Closing a window does not quit."
        )
    }
    static var screenshot: String { pick("截图", hant: "截圖", en: "Screenshot") }
    static func screenshotSettingsHelp(_ hotkey: String) -> String {
        pick(
            "截图（\(hotkey)）会冻结当前屏幕，拖出选区后可用矩形、箭头、马赛克、文字等标注，点 ✓ 后进入剪贴板与历史。之后在卡片上右键「识别文字」即可用 Vision 在本机识别画面文字。主窗口菜单里的「并识字」只保留文字、不存图片。",
            hant: "截圖（\(hotkey)）會凍結目前螢幕，拖出選區後可用矩形、箭頭、馬賽克、文字等標註，點 ✓ 後進入剪貼板與歷史。之後在卡片上按右鍵「辨識文字」即可用 Vision 在本機辨識畫面文字。主視窗選單裡的「並識字」只保留文字、不存圖片。",
            en: "Screenshot (\(hotkey)) freezes the screen. Drag a region, annotate with shapes, arrows, mosaic, or text, then tap ✓ to copy it into history. Later, right-click a card and choose Recognize text to read it on-device with Vision. “and recognize text” in the main window menu keeps only the words."
        )
    }
    static var globalHotkeys: String { pick("全局快捷键", hant: "全域快捷鍵", en: "Global hotkeys") }
    static func hotkeySummary(panel: String, window: String, shot: String) -> String {
        pick(
            "面板 \(panel) · 主窗口 \(window) · 截图 \(shot)",
            hant: "面板 \(panel) · 主視窗 \(window) · 截圖 \(shot)",
            en: "Panel \(panel) · Window \(window) · Screenshot \(shot)"
        )
    }
    static var modifyEllipsis: String { pick("修改…", hant: "修改…", en: "Edit…") }
    static var hotkeysPageHint: String {
        pick(
            "在「快捷键」页可重新录制，录下即刻生效。",
            hant: "在「快捷鍵」頁可重新錄製，錄下即刻生效。",
            en: "Re-record on the Hotkeys tab. Changes take effect immediately."
        )
    }
    static var permissions: String { pick("权限", hant: "權限", en: "Permissions") }
    static var accessibility: String { pick("辅助功能", hant: "輔助使用", en: "Accessibility") }
    static var accessibilityCaption: String {
        pick(
            "自动记录复制内容不需要辅助功能。只有「一键粘贴到其他 App」才需要。若列表里没有 PasteNest，先点此按钮再刷新列表。",
            hant: "自動記錄複製內容不需要輔助使用。只有「一鍵貼到其他 App」才需要。若列表裡沒有 PasteNest，先點此按鈕再重新整理列表。",
            en: "Watching the clipboard does not need Accessibility. Instant paste into other apps does. If PasteNest is missing from the list, tap this button, then refresh."
        )
    }
    static var allowInSystemSettings: String { pick("在系统设置中允许…", hant: "在系統設定中允許…", en: "Allow in System Settings…") }
    static var screenRecording: String { pick("屏幕录制", hant: "螢幕錄製", en: "Screen Recording") }
    static var screenRecordingCaption: String {
        pick(
            "截图需要「屏幕录制」权限。授权后需重新启动 PasteNest 才会生效。",
            hant: "截圖需要「螢幕錄製」權限。授權後需重新啟動 PasteNest 才會生效。",
            en: "Screenshots need Screen Recording access. Restart PasteNest after granting it."
        )
    }
    static var allowScreenshotInSystemSettings: String {
        pick("在系统设置中允许截图…", hant: "在系統設定中允許截圖…", en: "Allow screenshots in System Settings…")
    }
    static func generalFooter(panel: String, window: String) -> String {
        pick(
            "按 \(panel) 唤出底部面板，按 \(window) 唤出主窗口，也可点击右上角层叠图标。右键图标可退出。",
            hant: "按 \(panel) 喚出底部面板，按 \(window) 喚出主視窗，也可點擊右上角層疊圖示。對圖示按右鍵可結束。",
            en: "Press \(panel) for the shelf, \(window) for the main window, or click the stacked-squares icon. Right-click the icon to quit."
        )
    }
    static var version: String { pick("版本", hant: "版本", en: "Version") }
    static func versionBuild(_ version: String, build: String) -> String {
        pick(
            "\(version)（Build \(build)）",
            hant: "\(version)（Build \(build)）",
            en: "\(version) (Build \(build))"
        )
    }
    static var hotkeysHelp: String {
        pick(
            "点击组合键按钮，然后按下新的组合（需包含 ⌘ / ⌃ / ⌥ 中至少一个），按 Esc 取消。录下即刻生效，不用重启；被系统或其他 App 占用的组合会被拒绝并保留原快捷键。",
            hant: "點擊組合鍵按鈕，然後按下新的組合（需包含 ⌘ / ⌃ / ⌥ 中至少一個），按 Esc 取消。錄下即刻生效，不用重啟；被系統或其他 App 佔用的組合會被拒絕並保留原快捷鍵。",
            en: "Click a shortcut button, then press a new combo (it must include ⌘, ⌃, or ⌥). Esc cancels. Changes apply immediately. Combos already taken by the system or another app are rejected."
        )
    }
    static var restoreDefaults: String { pick("恢复默认", hant: "恢復預設", en: "Restore defaults") }
    static var restoreAllDefaults: String { pick("全部恢复默认", hant: "全部恢復預設", en: "Restore all defaults") }
    static var retention: String { pick("收藏与保留", hant: "收藏與保留", en: "Saved & retention") }
    static func keepUnfavorited(_ days: Int) -> String {
        pick(
            "未收藏的内容保留 \(days) 天",
            hant: "未收藏的內容保留 \(days) 天",
            en: days == 1 ? "Unsaved items stay 1 day" : "Unsaved items stay \(days) days"
        )
    }
    static func retentionHelp(_ days: Int) -> String {
        pick(
            "收藏夹里的内容长期保存；其余记录在最后一次使用满 \(days) 天后自动删除（置顶的也会保留）。粘贴或再次复制都会重新计时。",
            hant: "收藏夾裡的內容長期保存；其餘記錄在最後一次使用滿 \(days) 天後自動刪除（置頂的也會保留）。貼上或再次複製都會重新計時。",
            en: "Saved items stay. Everything else is deleted \(days) day\(days == 1 ? "" : "s") after last use (pins are kept). Pasting or copying again resets the timer."
        )
    }
    static var sweepNow: String { pick("立即清理过期内容", hant: "立即清理過期內容", en: "Clear expired now") }
    static var capacity: String { pick("容量", hant: "容量", en: "Capacity") }
    static func maxItems(_ n: Int) -> String {
        pick(
            "最多保存 \(n) 条",
            hant: "最多儲存 \(n) 則",
            en: n == 1 ? "Keep at most 1 item" : "Keep at most \(n) items"
        )
    }
    static var capacityHelp: String {
        pick(
            "超出限制时会自动清理最早的记录，收藏与置顶不计入这个上限。图片按压缩格式保存（优先 PNG，过大则 JPEG），以减少内存和磁盘占用。",
            hant: "超出限制時會自動清理最早的記錄，收藏與置頂不計入這個上限。圖片依壓縮格式儲存（優先 PNG，過大則 JPEG），以減少記憶體和磁碟占用。",
            en: "Oldest items drop off when the limit is hit. Saved and pinned items are not counted. Images are stored compressed (PNG, or JPEG if large) to save memory and disk."
        )
    }
    static var exportJSON: String { pick("导出历史为 JSON…", hant: "匯出歷史為 JSON…", en: "Export history as JSON…") }
    static var iCloud: String { pick("iCloud", hant: "iCloud", en: "iCloud") }
    static var iCloudSync: String { pick("通过 iCloud 同步", hant: "透過 iCloud 同步", en: "Sync with iCloud") }
    static var iCloudSyncCaption: String {
        pick(
            "启用后，剪贴板历史将通过你的 iCloud 账号在多台 Mac 间同步。请确保已登录同一 Apple ID。",
            hant: "啟用後，剪貼板歷史會透過你的 iCloud 帳號在多台 Mac 間同步。請確保已登入同一 Apple ID。",
            en: "When on, clipboard history syncs across your Macs with the same iCloud account. Sign in with the same Apple ID."
        )
    }
    static var status: String { pick("状态", hant: "狀態", en: "Status") }
    static var aboutTagline: String {
        pick("保存、搜索、同步你复制的一切", hant: "儲存、搜尋、同步你複製的一切", en: "Save, search, and sync everything you copy")
    }
    static func versionLabel(_ version: String) -> String {
        pick("版本 \(version)", hant: "版本 \(version)", en: "Version \(version)")
    }
    static var copyVersion: String { pick("复制版本信息", hant: "複製版本資訊", en: "Copy version info") }
    static func hotkeyLive(_ display: String) -> String {
        pick("已生效 \(display)", hant: "已生效 \(display)", en: "Active \(display)")
    }
    static var hotkeyUnregistered: String { pick("未注册", hant: "未註冊", en: "Not registered") }
    static var allowed: String { pick("已允许", hant: "已允許", en: "Allowed") }
    static var notAllowed: String { pick("未允许", hant: "未允許", en: "Not allowed") }

    static var syncIdle: String { pick("待命", hant: "待命", en: "Idle") }
    static var syncing: String { pick("同步中…", hant: "同步中…", en: "Syncing…") }
    static func syncedAgo(_ relative: String) -> String {
        pick("已同步 · \(relative)", hant: "已同步 · \(relative)", en: "Synced · \(relative)")
    }
    static var offline: String { pick("离线", hant: "離線", en: "Offline") }
    static func syncFailed(_ message: String) -> String {
        pick("同步失败 · \(message)", hant: "同步失敗 · \(message)", en: "Sync failed · \(message)")
    }

    // MARK: - Menus

    static func showPanel(_ hint: String) -> String {
        pick("显示剪贴板面板\(hint)", hant: "顯示剪貼板面板\(hint)", en: "Show clipboard shelf\(hint)")
    }
    static func showMainWindow(_ hint: String) -> String {
        pick("显示主窗口\(hint)", hant: "顯示主視窗\(hint)", en: "Show main window\(hint)")
    }
    static func openMainWindow(_ hint: String) -> String {
        pick("打开主窗口\(hint)", hant: "打開主視窗\(hint)", en: "Open main window\(hint)")
    }
    static var hidePanel: String { pick("隐藏面板", hant: "隱藏面板", en: "Hide shelf") }
    static func captureRegion(_ hint: String) -> String {
        pick("截取区域\(hint)", hant: "截取區域\(hint)", en: "Capture region\(hint)")
    }
    static var captureWindow: String { pick("截取窗口", hant: "截取視窗", en: "Capture window") }
    static var captureFullScreen: String { pick("截取整屏", hant: "截取整屏", en: "Capture full screen") }
    static var quitPasteNest: String { pick("退出 PasteNest", hant: "結束 PasteNest", en: "Quit PasteNest") }
    static var pauseMonitoring: String { pick("暂停监听", hant: "暫停監聽", en: "Pause watching") }
    static var resumeMonitoring: String { pick("恢复监听", hant: "恢復監聽", en: "Resume watching") }
    static var monitoringOn: String { pick("监听中", hant: "監聽中", en: "Watching") }
    static func statusTooltip(_ hotkey: String) -> String {
        pick(
            "PasteNest — 常驻后台（\(hotkey) 唤出）",
            hant: "PasteNest — 常駐背景（\(hotkey) 喚出）",
            en: "PasteNest — stays in the menu bar (\(hotkey) to show)"
        )
    }

    // MARK: - Hotkeys

    static var hotkeyPanel: String { pick("唤出剪贴板面板", hant: "喚出剪貼板面板", en: "Show clipboard shelf") }
    static var hotkeyMainWindow: String { pick("唤出主窗口", hant: "喚出主視窗", en: "Show main window") }
    static var hotkeyScreenshot: String { pick("截图（区域）", hant: "截圖（區域）", en: "Screenshot (region)") }
    static var hotkeyPanelShort: String { pick("剪贴板面板", hant: "剪貼板面板", en: "clipboard shelf") }
    static var hotkeyMainWindowShort: String { pick("主窗口", hant: "主視窗", en: "main window") }
    static var hotkeyScreenshotShort: String { pick("截图", hant: "截圖", en: "screenshot") }
    static var pressNewHotkey: String { pick("按下新快捷键…", hant: "按下新快捷鍵…", en: "Press a new shortcut…") }
    static var hotkeyNeedKey: String {
        pick(
            "请在按住修饰键的同时按一个字母、数字或功能键",
            hant: "請在按住修飾鍵的同時按一個字母、數字或功能鍵",
            en: "Hold a modifier and press a letter, number, or function key"
        )
    }
    static var hotkeyNeedModifier: String {
        pick(
            "快捷键需要包含 ⌘ / ⌃ / ⌥ 中的至少一个",
            hant: "快捷鍵需要包含 ⌘ / ⌃ / ⌥ 中的至少一個",
            en: "A shortcut needs at least one of ⌘, ⌃, or ⌥"
        )
    }
    static func hotkeyReserved(_ name: String) -> String {
        pick(
            "\(name) 已被系统占用，请换一个组合",
            hant: "\(name) 已被系統佔用，請換一個組合",
            en: "\(name) is reserved by the system. Pick another combo."
        )
    }
    static var reservedSpotlight: String { pick("⌘Space（聚焦搜索）", hant: "⌘Space（聚焦搜尋）", en: "⌘Space (Spotlight)") }
    static var reservedAppSwitch: String { pick("⌘⇥（切换 App）", hant: "⌘⇥（切換 App）", en: "⌘⇥ (switch apps)") }
    static var reservedQuit: String { pick("⌘Q（退出 App）", hant: "⌘Q（結束 App）", en: "⌘Q (Quit)") }
    static var reservedShot3: String { pick("⇧⌘3（截屏）", hant: "⇧⌘3（截屏）", en: "⇧⌘3 (screenshot)") }
    static var reservedShot4: String { pick("⇧⌘4（截屏）", hant: "⇧⌘4（截屏）", en: "⇧⌘4 (screenshot)") }
    static var reservedShot5: String { pick("⇧⌘5（截屏）", hant: "⇧⌘5（截屏）", en: "⇧⌘5 (screenshot)") }
    static func hotkeyClash(_ other: String) -> String {
        pick(
            "与「\(other)」快捷键相同，请换一个",
            hant: "與「\(other)」快捷鍵相同，請換一個",
            en: "Same as the \(other) shortcut. Pick another combo."
        )
    }
    static var hotkeyRegisterFailed: String {
        pick(
            "无法注册全局快捷键，请重启 PasteNest 后重试",
            hant: "無法註冊全域快捷鍵，請重啟 PasteNest 後重試",
            en: "Could not register the global shortcut. Restart PasteNest and try again."
        )
    }
    static var hotkeyTaken: String {
        pick("该组合已被其他 App 占用，请换一个", hant: "該組合已被其他 App 佔用，請換一個", en: "Another app already uses this combo. Pick another.")
    }
    static func hotkeyRestored(from stored: String, to fallback: String) -> String {
        pick(
            "原快捷键 \(stored) 已被占用，已恢复为 \(fallback)",
            hant: "原快捷鍵 \(stored) 已被佔用，已恢復為 \(fallback)",
            en: "\(stored) was taken, so it was restored to \(fallback)"
        )
    }
    static func hotkeyTakenPleaseChange(_ display: String) -> String {
        pick(
            "\(display) 已被占用，请设置一个新组合",
            hant: "\(display) 已被佔用，請設定一個新組合",
            en: "\(display) is taken. Set a new combo."
        )
    }
    static func hotkeyApplied(_ display: String) -> String {
        pick("已生效：\(display)", hant: "已生效：\(display)", en: "Active: \(display)")
    }

    // MARK: - Main window

    static var list: String { pick("列表", hant: "列表", en: "List") }
    static var timelineOutline: String { pick("时间线大纲", hant: "時間線大綱", en: "Timeline outline") }
    static var library: String { pick("资料库", hant: "資料庫", en: "Library") }
    static var boards: String { pick("看板", hant: "看板", en: "Boards") }
    static var autoTags: String { pick("自动标签", hant: "自動標籤", en: "Auto tags") }
    static var views: String { pick("视图", hant: "檢視", en: "Views") }
    static var clearTagFilter: String { pick("清除标签筛选", hant: "清除標籤篩選", en: "Clear tag filter") }
    static func favoritesKeepHelp(_ days: Int) -> String {
        pick(
            "收藏的内容长期保存，未收藏的只保留 \(days) 天。",
            hant: "收藏的內容長期保存，未收藏的只保留 \(days) 天。",
            en: "Saved items stay. Unsaved ones expire after \(days) day\(days == 1 ? "" : "s")."
        )
    }
    static func screenshotHelp(_ hotkey: String) -> String {
        pick(
            "截图（\(hotkey)）冻结屏幕、标注后存图片；「并识字」只存识别出的文字",
            hant: "截圖（\(hotkey)）凍結螢幕、標註後存圖片；「並識字」只存辨識出的文字",
            en: "Screenshot (\(hotkey)) freezes the screen and saves the image. “and recognize text” keeps only the words."
        )
    }
    static var andRecognize: String { pick("并识字", hant: "並識字", en: "and recognize text") }
    static func modeAndRecognize(_ title: String) -> String {
        pick("\(title)并识字", hant: "\(title)並識字", en: "\(title) and recognize text")
    }
    static var searchEverything: String { pick("搜索已复制的一切…", hant: "搜尋已複製的一切…", en: "Search everything you’ve copied…") }
    static var clearHistoryTitle: String { pick("清空历史？", hant: "清空歷史？", en: "Clear history?") }
    static var clearKeepPinned: String { pick("清空（保留置顶）", hant: "清空（保留置頂）", en: "Clear (keep pins)") }
    static var clearAll: String { pick("全部清空", hant: "全部清空", en: "Clear all") }
    static var clearHistoryMessage: String {
        pick(
            "此操作无法撤销。置顶条目可选择保留。",
            hant: "此操作無法復原。置頂條目可選擇保留。",
            en: "This cannot be undone. Pinned items can be kept."
        )
    }
    static func itemCount(_ n: Int) -> String {
        pick("\(n) 条", hant: "\(n) 則", en: n == 1 ? "1 item" : "\(n) items")
    }
    static var recentlyCopied: String { pick("最近复制", hant: "最近複製", en: "Recent") }
    static var startCopying: String { pick("开始复制吧", hant: "開始複製吧", en: "Copy something to get started") }
    static var emptyHistorySearch: String { pick("没有字面或相近的内容", hant: "沒有字面或相近的內容", en: "No literal or close matches") }
    static var emptyHistoryDetail: String {
        pick(
            "复制的文本、链接、图片与文件会自动打标签，并出现在时间线中。",
            hant: "複製的文字、連結、圖片與檔案會自動打標籤，並出現在時間線中。",
            en: "Copied text, links, images, and files are tagged automatically and show up on the timeline."
        )
    }
    static var emptyHistorySearchDetail: String {
        pick(
            "试试其他关键词、更口语的说法，或切换标签 / 时间线筛选。",
            hant: "試試其他關鍵詞、更口語的說法，或切換標籤 / 時間線篩選。",
            en: "Try another keyword, a more casual phrasing, or a different tag / timeline filter."
        )
    }
    static var selectToPreview: String { pick("选择一条记录以预览", hant: "選擇一則記錄以預覽", en: "Select an item to preview") }
    static var openLinkHint: String {
        pick("点击打开链接，或直接粘贴到当前应用。", hant: "點擊打開連結，或直接貼上到目前的 App。", en: "Click to open the link, or paste it into the current app.")
    }
    static var source: String { pick("来源", hant: "來源", en: "Source") }
    static var copiedAt: String { pick("复制时间", hant: "複製時間", en: "Copied") }
    static var pasteCount: String { pick("粘贴次数", hant: "貼上次數", en: "Pastes") }
    static var retentionPolicy: String { pick("保存策略", hant: "儲存策略", en: "Retention") }
    static var path: String { pick("路径", hant: "路徑", en: "Path") }
    static var unknownApp: String { pick("未知应用", hant: "未知 App", en: "Unknown app") }
    static var noBoard: String { pick("无看板", hant: "無看板", en: "No board") }
    static var board: String { pick("看板", hant: "看板", en: "Board") }
    static var assignBoardHelp: String {
        pick("移到看板", hant: "移到看板", en: "Move to a board")
    }
    static func removeFromTag(_ tag: String) -> String {
        pick("移出「\(tag)」分类", hant: "移出「\(tag)」分類", en: "Remove from “\(tag)”")
    }
    static var favoriteTagHelp: String {
        pick("收藏夹分类（打标签会自动收藏）", hant: "收藏夾分類（打標籤會自動收藏）", en: "Saved tags (tagging also saves the item)")
    }
    static func recognizedHeadingCount(_ n: Int) -> String {
        pick("识别到的文字 · \(n) 字", hant: "辨識到的文字 · \(n) 字", en: n == 1 ? "Recognized text · 1 char" : "Recognized text · \(n) chars")
    }
    static var filterSnippet: String { pick("长文本", hant: "長文字", en: "Long text") }

    static var tagWork: String { pick("工作", hant: "工作", en: "Work") }
    static var tagIdeas: String { pick("灵感", hant: "靈感", en: "Ideas") }
    static var tagCode: String { pick("代码", hant: "程式碼", en: "Code") }
    static var tagFiles: String { pick("资料", hant: "資料", en: "Files") }
    static var tagTodo: String { pick("待办", hant: "待辦", en: "To-do") }
}
