import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var syncService = SyncService()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
            historyTab
                .tabItem { Label("历史", systemImage: "clock") }
            syncTab
                .tabItem { Label("同步", systemImage: "icloud") }
            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 320)
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
            Toggle("登录时启动", isOn: $appState.launchAtLogin)
                .onChange(of: appState.launchAtLogin) { _, enabled in
                    appState.savePreferences()
                    updateLaunchAtLogin(enabled)
                }
            LabeledContent("快捷键", value: appState.hotkeyDisplay)
            Text("面板入口：屏幕右上角菜单栏的剪贴板图标，或按 ⇧⌘V。若图标被隐藏，点菜单栏「」并勾选 Paste。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("权限") {
                LabeledContent("辅助功能") {
                    Text(AccessibilityPermission.isTrusted ? "已允许" : "未允许")
                        .foregroundStyle(AccessibilityPermission.isTrusted ? Color.secondary : Color.orange)
                }
                Button("在系统设置中允许 Paste…") {
                    AccessibilityPermission.requestIfNeeded(prompt: true)
                    AccessibilityPermission.openSystemSettings()
                }
                Text("自动记录复制内容不需要辅助功能。只有「一键粘贴到其他 App」才需要。若列表里没有 Paste，先点此按钮再刷新列表。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("请点击屏幕右上角剪贴板图标，或按 ⇧⌘V 打开面板。复制（⌘C）后稍等半秒，再点图标或按 ⇧⌘V 查看历史。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .formStyle(.grouped)
    }

    private var historyTab: some View {
        Form {
            Stepper(value: $appState.maxHistoryCount, in: 50...5000, step: 50) {
                Text("最多保存 \(appState.maxHistoryCount) 条")
            }
            .onChange(of: appState.maxHistoryCount) { _, _ in
                appState.savePreferences()
            }
            Button("导出历史为 JSON…") {
                appState.requestExportJSON = true
            }
            Text("超出限制时会自动清理最早的非置顶记录。图片与文件会占用更多磁盘空间。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 42))
                .foregroundStyle(PasteTheme.accent)
            Text("Paste")
                .font(.title.weight(.bold))
            Text("保存、搜索、同步你复制的一切")
                .foregroundStyle(.secondary)
            Text("版本 1.0.3")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
