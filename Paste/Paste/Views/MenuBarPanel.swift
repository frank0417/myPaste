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
        Array(ClipboardItemFilter.filter(items, appState: appState).prefix(appState.panelViewMode == .shelf ? 40 : 200))
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                AutoTagFilterBar(items: items, compact: true)
                if appState.panelViewMode == .shelf {
                    shelf
                } else {
                    TimelineOutlineView(
                        items: filtered,
                        store: store,
                        onOpenDetail: { item in
                            appState.selectedItemID = item.id
                            appState.shelfDetailItemID = item.id
                        }
                    )
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 20, y: 8)

            if let detailItem = detailItem {
                ClipboardItemDetailOverlay(
                    item: detailItem,
                    onClose: { appState.shelfDetailItemID = nil },
                    onCopy: { copyOnlyItem(detailItem) },
                    onPaste: { paste(detailItem) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.shelfDetailItemID)
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
        .onChange(of: items.map(\.id)) { _, ids in
            if let detailID = appState.shelfDetailItemID, !ids.contains(detailID) {
                appState.shelfDetailItemID = nil
            }
        }
        .onChange(of: appState.shelfDetailItemID) { _, id in
            StatusItemController.shared.setExpandedForDetail(id != nil)
        }
        .onAppear {
            StatusItemController.shared.setExpandedForDetail(appState.shelfDetailItemID != nil)
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
            if appState.shelfDetailItemID != nil, let item = detailItem {
                paste(item)
            } else {
                pasteSelected()
            }
            return .handled
        }
    }

    private var detailItem: ClipboardItem? {
        guard let id = appState.shelfDetailItemID else { return nil }
        return items.first(where: { $0.id == id })
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

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    appState.panelViewMode = .shelf
                }
            } label: {
                tabPill(title: "卡片", systemImage: "square.grid.2x2", selected: appState.panelViewMode == .shelf)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    appState.panelViewMode = .timeline
                    if showSearch == false, !appState.searchQuery.isEmpty {
                        showSearch = true
                    }
                }
            } label: {
                tabPill(title: "时间线", systemImage: "calendar.day.timeline.leading", selected: appState.panelViewMode == .timeline)
            }
            .buttonStyle(.plain)

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
                            onOpenDetail: {
                                appState.selectedItemID = item.id
                                appState.shelfDetailItemID = item.id
                            },
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

    private func copyOnlyItem(_ item: ClipboardItem) {
        store?.copyOnly(item)
    }

    private func paste(_ item: ClipboardItem) {
        store?.paste(item)
        appState.shelfDetailItemID = nil
        StatusItemController.shared.hidePanel()
    }
}

struct ClipboardItemDetailOverlay: View {
    let item: ClipboardItem
    let onClose: () -> Void
    let onCopy: () -> Void
    let onPaste: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 0) {
                detailHeader
                Divider()
                ScrollView {
                    detailBody
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                Divider()
                detailFooter
            }
            .frame(maxWidth: 640, maxHeight: .infinity)
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.regularMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 24, y: 12)
            .padding(16)
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Label(item.contentType.displayName, systemImage: item.contentType.systemImage)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    (Color(hex: item.contentType.accentHex) ?? PasteTheme.accent).opacity(0.14),
                    in: Capsule()
                )
                .foregroundStyle(Color(hex: item.contentType.accentHex) ?? PasteTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewTitle)
                    .font(.headline)
                    .lineLimit(1)
                if let source = item.sourceAppName {
                    Text(source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭 (Esc)")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var detailBody: some View {
        switch item.contentType {
        case .image:
            if let data = item.imageData ?? item.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("无法预览图片")
                    .foregroundStyle(.secondary)
            }
        case .color:
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: item.colorHex ?? "#888888") ?? .gray)
                .frame(height: 140)
                .overlay(alignment: .bottomLeading) {
                    Text(item.colorHex ?? item.plainText ?? "")
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(14)
                }
        case .code:
            Text(item.plainText ?? "")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .link:
            VStack(alignment: .leading, spacing: 14) {
                if let urlString = item.plainText, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label(urlString, systemImage: "arrow.up.right.square")
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.leading)
                    }
                    Text(url.host ?? urlString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(item.plainText ?? item.previewTitle)
                        .font(.body)
                        .textSelection(.enabled)
                }
                Text(item.plainText ?? "")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .file:
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.fileURLs, id: \.absoluteString) { url in
                    Label(url.path, systemImage: "doc")
                        .font(.callout)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Text(item.plainText ?? item.previewTitle)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var detailFooter: some View {
        HStack(spacing: 10) {
            Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onCopy) {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            Button(action: onPaste) {
                Label("粘贴", systemImage: "return")
            }
            .buttonStyle(.borderedProminent)
            .tint(PasteTheme.accent)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

struct ClipboardShelfCard: View {
    let item: ClipboardItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenDetail: () -> Void
    let onPaste: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    private var characterCount: Int {
        item.plainText?.count ?? item.previewTitle.count
    }

    var body: some View {
        Button(action: onSelect) {
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
                    if let tag = item.primaryAutoTag {
                        Text(tag.displayName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                (Color(hex: tag.accentHex) ?? PasteTheme.accent).opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(Color(hex: tag.accentHex) ?? PasteTheme.accent)
                    }
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
            TapGesture(count: 2).onEnded { onOpenDetail() }
        )
        .contextMenu {
            Button("查看详情", action: onOpenDetail)
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
