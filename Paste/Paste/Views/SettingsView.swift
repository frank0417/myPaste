import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var syncService = SyncService()

    var body: some View {
        TabView(selection: $appState.settingsTab) {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(AppState.SettingsTab.general)
            hotkeysTab
                .tabItem { Label("快捷键", systemImage: "keyboard") }
                .tag(AppState.SettingsTab.hotkeys)
            historyTab
                .tabItem { Label("历史", systemImage: "clock") }
                .tag(AppState.SettingsTab.history)
            syncTab
                .tabItem { Label("同步", systemImage: "icloud") }
                .tag(AppState.SettingsTab.sync)
            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(AppState.SettingsTab.about)
        }
        .frame(width: 520, height: 400)
        .onAppear { syncService.startStatusHeartbeat() }
    }

    private var generalTab: some View {
        Form {
            Toggle("监听剪贴板", isOn: $appState.isMonitoringEnabled)
                .onChange(of: appState.isMonitoringEnabled) { _, enabled in
                    appState.savePreferences()
                    NotificationCenter.default.post(
                        name: .pasteMonitoringPreferenceChanged,
                        object: nil,
                        userInfo: ["enabled": enabled]
                    )
                }
            Text("复制后会按类型自动打标签（图片、链接、富文本等），可在时间线或标签栏筛选。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("截图（\(appState.screenshotHotkeyDisplay)）保存图片；之后在卡片上右键「识别文字」即可用 Vision 在本机识别画面文字（中英文）。菜单里的「截取区域并识字」则只保留文字、不存图片。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("登录时启动", isOn: $appState.launchAtLogin)
                .onChange(of: appState.launchAtLogin) { _, enabled in
                    appState.savePreferences()
                    updateLaunchAtLogin(enabled)
                }
            Section("快捷键") {
                LabeledContent("全局快捷键") {
                    Button("修改…") {
                        appState.settingsTab = .hotkeys
                    }
                }
                Text("面板 \(appState.hotkeyDisplay) · 主窗口 \(appState.mainWindowHotkeyDisplay) · 截图 \(appState.screenshotHotkeyDisplay)。在「快捷键」页可重新录制，录下即刻生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("权限") {
                LabeledContent("辅助功能") {
                    Text(AccessibilityPermission.isTrusted ? "已允许" : "未允许")
                        .foregroundStyle(AccessibilityPermission.isTrusted ? Color.secondary : Color.orange)
                }
                Button("在系统设置中允许 PasteNest…") {
                    AccessibilityPermission.requestIfNeeded(prompt: true)
                    AccessibilityPermission.openSystemSettings()
                }
                Text("自动记录复制内容不需要辅助功能。只有「一键粘贴到其他 App」才需要。若列表里没有 PasteNest，先点此按钮再刷新列表。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("屏幕录制") {
                    Text(ScreenshotService.hasScreenRecordingAccess ? "已允许" : "未允许")
                        .foregroundStyle(ScreenshotService.hasScreenRecordingAccess ? Color.secondary : Color.orange)
                }
                Button("在系统设置中允许截图…") {
                    ScreenshotService.requestScreenRecordingAccess()
                }
                Text("截图需要「屏幕录制」权限。授权后需重新启动 PasteNest 才会生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("PasteNest 常驻菜单栏后台，关掉窗口不会退出：按 \(appState.hotkeyDisplay) 唤出底部面板，按 \(appState.mainWindowHotkeyDisplay) 唤出主窗口，也可点击右上角层叠图标。右键图标可退出。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .formStyle(.grouped)
    }

    /// Every global shortcut in one place. Recording a combo registers it with the
    /// system immediately; the row shows the combo that is actually live.
    private var hotkeysTab: some View {
        Form {
            Section {
                ForEach(HotKeyAction.allCases) { action in
                    hotkeyRow(action)
                }
            } header: {
                Text("全局快捷键")
            } footer: {
                Text("点击组合键按钮，然后按下新的组合（需包含 ⌘ / ⌃ / ⌥ 中至少一个），按 Esc 取消。录下即刻生效，不用重启；被系统或其他 App 占用的组合会被拒绝并保留原快捷键。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("全部恢复默认") {
                    appState.resetHotkeysToDefaults()
                }
                .disabled(HotKeyAction.allCases.allSatisfy { appState.shortcut(for: $0) == $0.defaultShortcut })
                Text("面板与主窗口不会同时出现：唤出其中一个会自动收起另一个。截图直接进入区域选择，按 Esc 放弃本次截图；识字不需要单独的快捷键，截完在卡片上选「识别文字」即可。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .formStyle(.grouped)
    }

    private var historyTab: some View {
        Form {
            Section("收藏与保留") {
                Stepper(
                    value: $appState.keepUnfavoritedDays,
                    in: RetentionPolicy.minimumDays...RetentionPolicy.maximumDays
                ) {
                    Text("未收藏的内容保留 \(appState.keepUnfavoritedDays) 天")
                }
                .onChange(of: appState.keepUnfavoritedDays) { _, _ in
                    appState.savePreferences()
                    // Shortening the window should take effect now, not at the next copy.
                    NotificationCenter.default.post(name: .pasteRetentionSweepRequested, object: nil)
                }
                Button("立即清理过期内容") {
                    NotificationCenter.default.post(name: .pasteRetentionSweepRequested, object: nil)
                }
                Text("收藏夹里的内容长期保存；其余记录在最后一次使用满 \(appState.keepUnfavoritedDays) 天后自动删除（置顶的也会保留）。粘贴或再次复制都会重新计时。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("容量") {
                Stepper(value: $appState.maxHistoryCount, in: 50...5000, step: 50) {
                    Text("最多保存 \(appState.maxHistoryCount) 条")
                }
                .onChange(of: appState.maxHistoryCount) { _, _ in
                    appState.savePreferences()
                }
                Button("导出历史为 JSON…") {
                    appState.requestExportJSON = true
                }
                Text("超出限制时会自动清理最早的记录，收藏与置顶不计入这个上限。图片与文件会占用更多磁盘空间。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .formStyle(.grouped)
    }

    private var syncTab: some View {
        Form {
            Toggle("通过 iCloud 同步", isOn: $appState.syncEnabled)
                .onChange(of: appState.syncEnabled) { _, _ in
                    appState.savePreferences()
                    syncService.markSyncing()
                }
            LabeledContent("状态") {
                Text(syncService.status.label)
                    .foregroundStyle(.secondary)
            }
            Text("启用后，剪贴板历史将通过你的 iCloud 账号在多台 Mac 间同步。请确保已登录同一 Apple ID。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .formStyle(.grouped)
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 42))
                .foregroundStyle(PasteTheme.accent)
            Text("PasteNest")
                .font(.title.weight(.bold))
            Text("保存、搜索、同步你复制的一切")
                .foregroundStyle(.secondary)
            Text("版本 \(Self.appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hotkeyRow(_ action: HotKeyAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                HotKeyRecorderView(action: action, shortcut: shortcutBinding(action)) { newShortcut in
                    appState.updateHotkey(newShortcut, for: action)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                    liveStatus(action)
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

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

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
}
