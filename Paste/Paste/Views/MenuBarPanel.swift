import SwiftUI
import SwiftData
import AppKit
import ServiceManagement

struct MenuBarPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.updatedAt, order: .reverse) private var items: [ClipboardItem]
    @State private var store: ClipboardStore?
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @State private var dismissLaunchCard = UserDefaults.standard.bool(forKey: "dismissedLaunchAtLoginCard")
    @State private var acknowledgedBackgroundTip = UserDefaults.standard.bool(forKey: "acknowledgedBackgroundTip")

    private var filtered: [ClipboardItem] {
        let q = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            guard !q.isEmpty else { return true }
            let hay = [item.previewTitle, item.plainText, item.sourceAppName]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            return hay.contains(q)
        }
        .prefix(40)
        .map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            shelf
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 28, y: 10)
        }
        .padding(6)
        .onAppear {
            if store == nil {
                store = ClipboardStore(modelContext: modelContext, appState: appState, ownsMonitor: false)
            }
            if appState.selectedItemID == nil {
                appState.selectedItemID = filtered.first?.id
            }
        }
        .onChange(of: filtered.map(\.id)) { _, ids in
            if let selected = appState.selectedItemID, ids.contains(selected) { return }
            appState.selectedItemID = ids.first
        }
        .focusable()
        .onKeyPress(.leftArrow) {
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            pasteSelected()
            return .handled
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showSearch.toggle()
                    searchFocused = showSearch
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("搜索")

            if showSearch {
                TextField("搜索剪贴板…", text: $appState.searchQuery)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .frame(maxWidth: 220)
                    .focused($searchFocused)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            tabPill(title: "剪贴板", systemImage: "clock.arrow.circlepath", selected: true)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isMonitoringEnabled ? Color.green.opacity(0.9) : Color.orange.opacity(0.9))
                    .frame(width: 7, height: 7)
                Text(appState.isMonitoringEnabled ? "后台监听中" : "已暂停")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(appState.hotkeyDisplay)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Menu {
                Button("粘贴选中项") { pasteSelected() }
                Button(appState.isMonitoringEnabled ? "暂停监听" : "恢复监听") {
                    appState.isMonitoringEnabled.toggle()
                    appState.savePreferences()
                    NotificationCenter.default.post(
                        name: .pasteMonitoringPreferenceChanged,
                        object: nil,
                        userInfo: ["enabled": appState.isMonitoringEnabled]
                    )
                }
                Divider()
                Button("打开设置…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Button("隐藏面板") {
                    StatusItemController.shared.hidePanel()
                }
                Divider()
                Button("退出 Paste", role: .destructive) {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private func tabPill(title: String, systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(selected ? Color.primary.opacity(0.08) : Color.clear)
        )
    }

    private var shelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 14) {
                if shouldShowLaunchCard {
                    onboardingCard(
                        icon: "power",
                        title: "登录时打开",
                        detail: "重启 Mac 后自动启动 Paste，保持常驻后台。",
                        actionTitle: "启用"
                    ) {
                        enableLaunchAtLogin()
                    }
                }

                if !acknowledgedBackgroundTip {
                    onboardingCard(
                        icon: "waveform.path.ecg",
                        title: "常驻后台",
                        detail: "关闭面板不会退出。按 \(appState.hotkeyDisplay) 随时唤出。",
                        actionTitle: "知道了"
                    ) {
                        acknowledgedBackgroundTip = true
                        UserDefaults.standard.set(true, forKey: "acknowledgedBackgroundTip")
                    }
                }

                if filtered.isEmpty {
                    emptyCard
                } else {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                        ClipboardShelfCard(
                            item: item,
                            index: index + 1,
                            isSelected: appState.selectedItemID == item.id,
                            onSelect: { appState.selectedItemID = item.id },
                            onPaste: { paste(item) },
                            onPin: { store?.togglePin(item) },
                            onDelete: { store?.delete(item) }
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.top, 4)
        }
    }

    private var shouldShowLaunchCard: Bool {
        !dismissLaunchCard && !appState.launchAtLogin
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(PasteTheme.accent)
            Text("复制任意内容后会出现在这里")
                .font(.callout.weight(.medium))
            Text("面板可随时关闭，App 继续在菜单栏后台运行")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(width: 220, height: 220)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func onboardingCard(
        icon: String,
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(title)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(PasteTheme.accent)
                .controlSize(.small)
        }
        .padding(16)
        .frame(width: 168, height: 220, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func enableLaunchAtLogin() {
        do {
            try SMAppService.mainApp.register()
            appState.launchAtLogin = true
            appState.savePreferences()
            dismissLaunchCard = true
            UserDefaults.standard.set(true, forKey: "dismissedLaunchAtLoginCard")
        } catch {
            #if DEBUG
            print("Launch at login failed: \(error)")
            #endif
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let ids = filtered.map(\.id)
        let current = appState.selectedItemID.flatMap { ids.firstIndex(of: $0) } ?? 0
        let next = min(max(current + delta, 0), ids.count - 1)
        appState.selectedItemID = ids[next]
    }

    private func pasteSelected() {
        guard let id = appState.selectedItemID,
              let item = filtered.first(where: { $0.id == id }) else { return }
        paste(item)
    }

    private func paste(_ item: ClipboardItem) {
        store?.paste(item)
        StatusItemController.shared.hidePanel()
    }
}

struct ClipboardShelfCard: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var characterCount: Int {
        item.plainText?.count ?? item.previewTitle.count
    }

    var body: some View {
        Button {
            if isSelected {
                onPaste()
            } else {
                onSelect()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.contentType.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(item.updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 4)
                    sourceBadge
                }

                Spacer(minLength: 8)

                previewBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Spacer(minLength: 8)

                HStack {
                    Text("\(characterCount) 个字符")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(PasteTheme.accent)
                    }
                    Text("\(index)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(width: 168, height: 220, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.12 : 0.06),
                        lineWidth: isSelected ? 3 : 1
                    )
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.18) : .clear, radius: 10, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { onPaste() }
        )
        .contextMenu {
            Button("粘贴", action: onPaste)
            Button(item.isPinned ? "取消置顶" : "置顶", action: onPin)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSelected)
    }

    @ViewBuilder
    private var previewBody: some View {
        if item.contentType == .image, let data = item.thumbnailData ?? item.imageData,
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: 120)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if item.contentType == .color, let hex = item.colorHex {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: hex) ?? .gray)
                .frame(height: 72)
        } else {
            Text(item.plainText ?? item.previewTitle)
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundStyle(.primary)
                .lineLimit(8)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder
    private var sourceBadge: some View {
        if let name = item.sourceAppName, !name.isEmpty {
            Image(systemName: "app.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .help(name)
        } else {
            Image(systemName: item.contentType.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}
