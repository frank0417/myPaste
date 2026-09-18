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
            settingsCard(PanelL10n.preferences) {
                toggleRow(
                    title: PanelL10n.listenClipboard,
                    caption: PanelL10n.listenClipboardCaption,
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
                    title: PanelL10n.launchAtLogin,
                    caption: PanelL10n.launchAtLoginCaption,
                    isOn: $appState.launchAtLogin
                ) { enabled in
                    appState.savePreferences()
                    updateLaunchAtLogin(enabled)
                }
            }

            settingsCard(PanelL10n.screenshot) {
                Text(PanelL10n.screenshotSettingsHelp(appState.screenshotHotkeyDisplay))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            settingsCard(PanelL10n.settingsTabHotkeys) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PanelL10n.globalHotkeys)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PasteTheme.ink)
                        Text(PanelL10n.hotkeySummary(
                            panel: appState.hotkeyDisplay,
                            window: appState.mainWindowHotkeyDisplay,
                            shot: appState.screenshotHotkeyDisplay
                        ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    settingsChip(PanelL10n.modifyEllipsis) {
                        appState.settingsTab = .hotkeys
                    }
                }
                Text(PanelL10n.hotkeysPageHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            settingsCard(PanelL10n.permissions) {
                permissionRow(
                    title: PanelL10n.accessibility,
                    allowed: AccessibilityPermission.isTrusted,
                    caption: PanelL10n.accessibilityCaption
                ) {
                    settingsChip(PanelL10n.allowInSystemSettings) {
                        AccessibilityPermission.requestIfNeeded(prompt: true)
                        AccessibilityPermission.openSystemSettings()
                    }
                }
                cardDivider
                permissionRow(
                    title: PanelL10n.screenRecording,
                    allowed: ScreenshotService.hasScreenRecordingAccess,
                    caption: PanelL10n.screenRecordingCaption
                ) {
                    settingsChip(PanelL10n.allowScreenshotInSystemSettings) {
                        ScreenshotService.requestScreenRecordingAccess()
                    }
                }
            }

            Text(PanelL10n.generalFooter(panel: appState.hotkeyDisplay, window: appState.mainWindowHotkeyDisplay))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)

            HStack {
                Text(PanelL10n.version)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(PanelL10n.versionBuild(Self.appVersion, build: Self.buildNumber))
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
            settingsCard(PanelL10n.globalHotkeys) {
                ForEach(Array(HotKeyAction.allCases.enumerated()), id: \.element.id) { index, action in
                    hotkeyRow(action)
                    if index < HotKeyAction.allCases.count - 1 {
                        cardDivider
                    }
                }
            }
            Text(PanelL10n.hotkeysHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            settingsCard {
                HStack {
                    Text(PanelL10n.restoreDefaults)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PasteTheme.ink)
                    Spacer(minLength: 8)
                    settingsChip(PanelL10n.restoreAllDefaults) {
                        appState.resetHotkeysToDefaults()
                    }
                }
            }
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard(PanelL10n.retention) {
                Stepper(
                    value: $appState.keepUnfavoritedDays,
                    in: RetentionPolicy.minimumDays...RetentionPolicy.maximumDays
                ) {
                    Text(PanelL10n.keepUnfavorited(appState.keepUnfavoritedDays))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PasteTheme.ink)
                }
                .onChange(of: appState.keepUnfavoritedDays) { _, _ in
                    appState.savePreferences()
                    NotificationCenter.default.post(name: .pasteRetentionSweepRequested, object: nil)
                }
                Text(PanelL10n.retentionHelp(appState.keepUnfavoritedDays))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                settingsChip(PanelL10n.sweepNow) {
                    NotificationCenter.default.post(name: .pasteRetentionSweepRequested, object: nil)
                }
            }

            settingsCard(PanelL10n.capacity) {
                Stepper(value: $appState.maxHistoryCount, in: 50...5000, step: 50) {
                    Text(PanelL10n.maxItems(appState.maxHistoryCount))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(PasteTheme.ink)
                }
                .onChange(of: appState.maxHistoryCount) { _, _ in
                    appState.savePreferences()
                }
                Text(PanelL10n.capacityHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                settingsChip(PanelL10n.exportJSON) {
                    appState.requestExportJSON = true
                }
            }
        }
    }

    private var syncTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsCard(PanelL10n.iCloud) {
                toggleRow(
                    title: PanelL10n.iCloudSync,
                    caption: PanelL10n.iCloudSyncCaption,
                    isOn: $appState.syncEnabled
                ) { _ in
                    appState.savePreferences()
                    syncService.markSyncing()
                }
                cardDivider
                HStack {
                    Text(PanelL10n.status)
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
                    Text(PanelL10n.aboutTagline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(PanelL10n.versionLabel(Self.appVersion))
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
                        .help(PanelL10n.copyVersion)
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
            Text(live.map { PanelL10n.hotkeyLive($0.display) } ?? PanelL10n.hotkeyUnregistered)
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
                Text(allowed ? PanelL10n.allowed : PanelL10n.notAllowed)
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
        case .general: return PanelL10n.settingsTabGeneral
        case .hotkeys: return PanelL10n.settingsTabHotkeys
        case .history: return PanelL10n.settingsTabHistory
        case .sync: return PanelL10n.settingsTabSync
        case .about: return PanelL10n.settingsTabAbout
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
