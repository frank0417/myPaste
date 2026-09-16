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

    static var clipboard: String { pick("剪贴板", hant: "剪貼板", en: "Clipboard") }
    static var favorites: String { pick("收藏夹", hant: "收藏夾", en: "Saved") }
    static var timeline: String { pick("时间线", hant: "時間線", en: "Timeline") }
    static var search: String { pick("搜索", hant: "搜尋", en: "Search") }
    static var collapseSearch: String { pick("收起搜索", hant: "收起搜尋", en: "Hide search") }
    static var clearSearch: String { pick("清空", hant: "清空", en: "Clear") }
    static var searchPlaceholder: String { pick("搜索剪贴板…", hant: "搜尋剪貼板…", en: "Search clipboard…") }
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
    static var backgroundTitle: String { pick("常驻后台", hant: "常駐背景", en: "Stays in the menu bar") }
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
    static var copyText: String { pick("复制文字", hant: "複製文字", en: "Copy text") }
    static var copyRecognized: String { pick("复制识别的文字", hant: "複製辨識的文字", en: "Copy recognized text") }
    static var recognizeText: String { pick("识别文字", hant: "辨識文字", en: "Recognize text") }
    static var recognizeHelp: String { pick("用 Vision 在本机识别这张截图里的文字", hant: "用 Vision 在本機辨識這張截圖裡的文字", en: "Recognize text in this screenshot on-device with Vision") }
    static var download: String { pick("下载", hant: "下載", en: "Download") }
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
}
