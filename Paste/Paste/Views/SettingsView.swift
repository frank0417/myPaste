import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var syncService = SyncService()

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            ScrollView {
                tabContent
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 22)
            }
        }
        .frame(width: 560, height: 560)
        .background(PasteTheme.backgroundGradient.ignoresSafeArea())
        .onAppear { syncService.startStatusHeartbeat() }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppState.SettingsTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        appState.settingsTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(appState.settingsTab == tab ? PasteTheme.ink : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(appState.settingsTab == tab ? Color.primary.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .tag(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .shelfPill()
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch appState.settingsTab {
        case .general: generalTab
        case .hotkeys: hotkeysTab
        case .history: historyTab
        case .sync: syncTab
        case .about: aboutTab
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard("偏好") {
                toggleRow(
                    title: "监听剪贴板",
                    caption: "复制后会按类型自动打标签（图片、链接、富文本等），可在时间线或标签栏筛选。",
                    isOn: $appState.isMonitoringEnabled
                ) { enabled in
                    appState.savePreferences()
                    NotificationCenter.default.post(
                        name: .pasteMonitoringPreferenceChanged,
                        object: nil,
                        userInfo: ["enabled": enabled]
                    )
                }
                cardDivider
                toggleRow(
                    title: "登录时启动",
                    caption: "PasteNest 常驻菜单栏后台，关掉窗口不会退出。",
                    isOn: $appState.launchAtLogin
                ) { enabled in
                    appState.savePreferences()
                    updateLaunchAtLogin(enabled)
                }
            }

            settingsCard("截图") {
                Text("截图（\(appState.screenshotHotkeyDisplay)）会冻结当前屏幕，拖出选区后可用矩形、箭头、马赛克、文字等标注，点 ✓ 后进入剪贴板与历史。之后在卡片上右键「识别文字」即可用 Vision 在本机识别画面文字（中英文）。菜单里的「截取区域并识字」则只保留文字、不存图片。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            settingsCard("快捷键") {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("全局快捷键")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PasteTheme.ink)
                        Text("面板 \(appState.hotkeyDisplay) · 主窗口 \(appState.mainWindowHotkeyDisplay) · 截图 \(appState.screenshotHotkeyDisplay)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    settingsChip("修改…") {
                        appState.settingsTab = .hotkeys
                    }
                }
                Text("在「快捷键」页可重新录制，录下即刻生效。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            settingsCard("权限") {
                permissionRow(
                    title: "辅助功能",
                    allowed: AccessibilityPermission.isTrusted,
                    caption: "自动记录复制内容不需要辅助功能。只有「一键粘贴到其他 App」才需要。若列表里没有 PasteNest，先点此按钮再刷新列表。"
                ) {
                    settingsChip("在系统设置中允许…") {
                        AccessibilityPermission.requestIfNeeded(prompt: true)
                        AccessibilityPermission.openSystemSettings()
                    }
                }
                cardDivider
                permissionRow(
                    title: "屏幕录制",
                    allowed: ScreenshotService.hasScreenRecordingAccess,
                    caption: "截图需要「屏幕录制」权限。授权后需重新启动 PasteNest 才会生效。"
                ) {
                    settingsChip("在系统设置中允许截图…") {
                        ScreenshotService.requestScreenRecordingAccess()
                    }
                }
            }

            Text("按 \(appState.hotkeyDisplay) 唤出底部面板，按 \(appState.mainWindowHotkeyDisplay) 唤出主窗口，也可点击右上角层叠图标。右键图标可退出。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)

            HStack {
                Text("版本")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Self.appVersion)（Build \(Self.buildNumber)）")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    /// Every global shortcut in one place. Recording a combo registers it with the
    /// system immediately; the row shows the combo that is actually live.
    private var hotkeysTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard("全局快捷键") {
                ForEach(Array(HotKeyAction.allCases.enumerated()), id: \.element.id) { index, action in
                    hotkeyRow(action)
                    if index < HotKeyAction.allCases.count - 1 {
                        cardDivider
                    }
                }
            }
            Text("点击组合键按钮，然后按下新的组合（需包含 ⌘ / ⌃ / ⌥ 中至少一个），按 Esc 取消。录下即刻生效，不用重启；被系统或其他 App 占用的组合会被拒绝并保留原快捷键。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            settingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("恢复默认")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PasteTheme.ink)
                        Text("面板与主窗口不会同时出现：唤出其中一个会自动收起另一个。截图会冻结屏幕并进入选区标注，按 Esc 放弃本次截图；识字不需要单独的快捷键，截完在卡片上选「识别文字」即可。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    settingsChip("全部恢复默认") {
                        appState.resetHotkeysToDefaults()
                    }
                    .disabled(HotKeyAction.allCases.allSatisfy { appState.shortcut(for: $0) == $0.defaultShortcut })
                    .opacity(
                        HotKeyAction.allCases.allSatisfy { appState.shortcut(for: $0) == $0.defaultShortcut }
                            ? 0.45 : 1
                    )
                }
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard("收藏与保留") {
                Stepper(
                    value: $appState.keepUnfavoritedDays,
                    in: RetentionPolicy.minimumDays...RetentionPolicy.maximumDays
                ) {
                    Text("未收藏的内容保留 \(appState.keepUnfavoritedDays) 天")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PasteTheme.ink)
                }
                .onChange(of: appState.keepUnfavoritedDays) { _, _ in
                    appState.savePreferences()
                    NotificationCenter.default.post(name: .pasteRetentionSweepRequested, object: nil)
                }
                Text("收藏夹里的内容长期保存；其余记录在最后一次使用满 \(appState.keepUnfavoritedDays) 天后自动删除（置顶的也会保留）。粘贴或再次复制都会重新计时。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                settingsChip("立即清理过期内容") {
                    NotificationCenter.default.post(name: .pasteRetentionSweepRequested, object: nil)
                }
            }

            settingsCard("容量") {
                Stepper(value: $appState.maxHistoryCount, in: 50...5000, step: 50) {
                    Text("最多保存 \(appState.maxHistoryCount) 条")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PasteTheme.ink)
                }
                .onChange(of: appState.maxHistoryCount) { _, _ in
                    appState.savePreferences()
                }
                Text("超出限制时会自动清理最早的记录，收藏与置顶不计入这个上限。图片按压缩格式保存（优先 PNG，过大则 JPEG），以减少内存和磁盘占用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                settingsChip("导出历史为 JSON…") {
                    appState.requestExportJSON = true
                }
            }
        }
    }

    private var syncTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard("iCloud") {
                toggleRow(
                    title: "通过 iCloud 同步",
                    caption: "启用后，剪贴板历史将通过你的 iCloud 账号在多台 Mac 间同步。请确保已登录同一 Apple ID。",
                    isOn: $appState.syncEnabled
                ) { _ in
                    appState.savePreferences()
                    syncService.markSyncing()
                }
                cardDivider
                HStack {
                    Text("状态")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PasteTheme.ink)
                    Spacer()
                    Text(syncService.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            settingsCard {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(PasteTheme.accent)
                    Text("PasteNest")
                        .font(.title.weight(.bold))
                        .foregroundStyle(PasteTheme.ink)
                    Text("保存、搜索、同步你复制的一切")
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text("版本 \(Self.appVersion)")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        Text("Build \(Self.buildNumber)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button {
                            copyVersionInfo()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("复制版本信息")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .shelfPill()
                    .padding(.top, 4)

                    Text("macOS \(Self.systemVersion)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }

    private func copyVersionInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AppVersion.report, forType: .string)
    }

    private func hotkeyRow(_ action: HotKeyAction) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PasteTheme.ink)
                    liveStatus(action)
                }
                Spacer(minLength: 8)
                HotKeyRecorderView(action: action, shortcut: shortcutBinding(action)) { newShortcut in
                    appState.updateHotkey(newShortcut, for: action)
                }
            }
            if let feedback = appState.hotkeyFeedback[action], feedback.isError {
                Label(feedback.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
        }
    }

    /// What the system is listening for right now — the proof that a change took.
    private func liveStatus(_ action: HotKeyAction) -> some View {
        let live = appState.liveShortcut(for: action)
        return HStack(spacing: 4) {
            Circle()
                .fill(live == nil ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(live.map { "已生效 \($0.display)" } ?? "未注册")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func shortcutBinding(_ action: HotKeyAction) -> Binding<HotKeyShortcut> {
        switch action {
        case .panel: return $appState.hotkey
        case .mainWindow: return $appState.mainWindowHotkey
        case .screenshot: return $appState.screenshotHotkey
        }
    }

    private static var appVersion: String { AppVersion.marketing }
    private static var buildNumber: String { AppVersion.build }
    private static var systemVersion: String { AppVersion.systemVersion }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            #if DEBUG
            print("Launch at login error: \(error)")
            #endif
        }
    }

    private var cardDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.06))
            .frame(height: 1)
    }

    private func settingsCard(_ title: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: PasteTheme.cardShape)
        .overlay(
            PasteTheme.cardShape
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func settingsChip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(PasteTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .shelfPill()
    }

    private func toggleRow(
        title: String,
        caption: String,
        isOn: Binding<Bool>,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PasteTheme.ink)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(PasteTheme.accent)
                .onChange(of: isOn.wrappedValue) { _, enabled in
                    onChange(enabled)
                }
        }
    }

    private func permissionRow(
        title: String,
        allowed: Bool,
        caption: String,
        @ViewBuilder action: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PasteTheme.ink)
                Spacer()
                Text(allowed ? "已允许" : "未允许")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(allowed ? PasteTheme.accent : Color.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill((allowed ? PasteTheme.accent : Color.orange).opacity(0.12))
                    )
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            action()
        }
    }
}

private extension AppState.SettingsTab {
    var title: String {
        switch self {
        case .general: return "通用"
        case .hotkeys: return "快捷键"
        case .history: return "历史"
        case .sync: return "同步"
        case .about: return "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .hotkeys: return "keyboard"
        case .history: return "clock"
        case .sync: return "icloud"
        case .about: return "info.circle"
        }
    }
}
