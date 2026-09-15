import SwiftUI
import SwiftData
import AppKit
import ServiceManagement

/// Reference-type memo so a computed view property can cache without mutating
/// @State during a body evaluation.
final class FilterMemo {
    var key: Int = -1
    var value: [ClipboardItem] = []
}

struct MenuBarPanel: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.updatedAt, order: .reverse) private var items: [ClipboardItem]
    @State private var store: ClipboardStore?
    /// The field owns its focus directly; the panel's NSPanel is non-activating, and
    /// routing focus through the view tree's @FocusState is unreliable there.
    @State private var searchField: NSTextField?
    @State private var draftQuery = ""
    @State private var searchDebounce: DispatchWorkItem?
    @State private var dismissLaunchCard = UserDefaults.standard.bool(forKey: "dismissedLaunchAtLoginCard")
    @State private var acknowledgedBackgroundTip = UserDefaults.standard.bool(forKey: "acknowledgedBackgroundTip")

    private var favorites: [ClipboardItem] {
        items.filter(\.isFavorite)
    }

    private var showSearch: Bool { appState.isPanelSearchVisible }

    /// `filtered` is read several times per body evaluation (list, count, change
    /// handlers). Ranking is pure given the inputs, so the result is memoized against
    /// a fingerprint of everything that can change the answer — including favorite
    /// and tag flips, which leave the id list untouched.
    /// @State keeps the memo alive across the struct's re-instantiations; mutating
    /// the referenced box during body is fine, only the wrapper must not change.
    @State private var filterMemo = FilterMemo()

    private var filtered: [ClipboardItem] {
        var hasher = Hasher()
        hasher.combine(appState.searchQuery)
        hasher.combine(appState.selectedFilter.rawValue)
        hasher.combine(appState.showOnlyPinned)
        hasher.combine(appState.showOnlyFavorites)
        hasher.combine(appState.favoriteScope)
        hasher.combine(appState.selectedAutoTag)
        hasher.combine(appState.embeddingRevision)
        hasher.combine(appState.panelViewMode.rawValue)
        for item in items {
            hasher.combine(item.id)
            hasher.combine(item.updatedAt)
            hasher.combine(item.isFavorite)
            hasher.combine(item.isPinned)
            hasher.combine(item.favoriteTagsJSON)
            hasher.combine(item.autoTagsJSON)
        }
        let key = hasher.finalize()
        if filterMemo.key == key { return filterMemo.value }
        let value = Array(
            ClipboardItemFilter.filter(items, appState: appState)
                .prefix(appState.panelViewMode == .timeline ? 200 : 40)
        )
        filterMemo.key = key
        filterMemo.value = value
        return value
    }

    var body: some View {
        ZStack {
            // When detail is open, hide the shelf layer completely so nothing shows through.
            if detailItem == nil {
                VStack(spacing: 2) {
                    // A standalone floating field above the nav bar, not part of the card.
                    if showSearch {
                        searchPill
                    }
                    panelCard
                }
                // Pin the content to the window's top and let the card take every
                // remaining point: a centered, shorter VStack leaves transparent bands
                // that read as detached capsules and broken corners.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(.easeOut(duration: 0.18), value: showSearch)
            }

            if let detailItem = detailItem {
                ClipboardItemDetailOverlay(
                    item: detailItem,
                    retentionDays: appState.keepUnfavoritedDays,
                    onClose: { appState.shelfDetailItemID = nil },
                    onCopy: { copyOnlyItem(detailItem) },
                    onCopyText: { store?.copyText(detailItem) },
                    onPaste: { paste(detailItem) },
                    onToggleFavorite: { store?.toggleFavorite(detailItem) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: appState.shelfDetailItemID)
        .onAppear {
            if store == nil {
                store = ClipboardStore(modelContext: modelContext, appState: appState, ownsMonitor: false)
            }
            // The panel is rebuilt on every show, and the favorites filter is shared with
            // the main window — re-apply whatever this tab means before the first render.
            if appState.panelViewMode == .favorites {
                appState.showFavorites(scope: appState.favoriteScope)
            } else {
                appState.leaveFavorites()
            }
            if appState.selectedItemID == nil {
                appState.selectedItemID = filtered.first?.id
            }
        }
        .onChange(of: appState.showOnlyFavorites) { _, only in
            // Keep the tab and the filter in step even when another surface flips it.
            if only, appState.panelViewMode != .favorites {
                appState.panelViewMode = .favorites
            } else if !only, appState.panelViewMode == .favorites {
                appState.panelViewMode = .shelf
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
        // While the search box is up it owns first responder; making the whole
        // panel focusable at the same time steals keystrokes back from the field.
        .focusable(!showSearch)
        .onKeyPress(.leftArrow) {
            guard !isSearchFieldEditing else { return .ignored }
            moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard !isSearchFieldEditing else { return .ignored }
            moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !isSearchFieldEditing else { return .ignored }
            if appState.shelfDetailItemID != nil, let item = detailItem {
                paste(item)
            } else {
                pasteSelected()
            }
            return .handled
        }
        .onKeyPress(.escape) {
            guard showSearch else { return .ignored }
            closeSearch()
            return .handled
        }
        .onKeyPress(keys: [.init("f")]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            openSearch()
            return .handled
        }
        .onChange(of: appState.isPanelSearchVisible) { _, visible in
            // The panel controller can close the box from its Escape monitor.
            if visible {
                focusSearchField()
            } else if !draftQuery.isEmpty {
                clearSearch()
            }
        }
    }

    /// Whether the search field's editor currently owns key events.
    private var isSearchFieldEditing: Bool {
        guard let window = searchField?.window else { return false }
        return window.firstResponder === searchField?.currentEditor()
    }

    /// The panel is a non-activating NSPanel: it must become key and the field must be
    /// made first responder, or every keystroke falls through to the app behind it.
    private func focusSearchField() {
        PanelSearchField.focus(searchField)
    }

    private var detailItem: ClipboardItem? {
        guard let id = appState.shelfDetailItemID else { return nil }
        return items.first(where: { $0.id == id })
    }

    private var panelCard: some View {
        VStack(spacing: 0) {
            topBar
            if appState.panelViewMode == .shelf {
                shelf
            } else if appState.panelViewMode == .favorites {
                FavoritesFolderView(
                    items: filtered,
                    favorites: favorites,
                    layout: .shelf,
                    store: store,
                    onOpenDetail: { item in
                        appState.selectedItemID = item.id
                        appState.shelfDetailItemID = item.id
                    },
                    onPaste: { paste($0) }
                )
            } else {
                AutoTagFilterBar(items: items, compact: true)
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
        // Fill the window so the rounded background *is* the panel: no dead band
        // below the shelf and no capsule floating outside the card. The card runs
        // edge to edge with no shadow: a shadow cut off by the window bounds shows
        // up as a translucent frame around the panel.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PasteTheme.panelFill.opacity(0.92))
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                if showSearch {
                    closeSearch()
                } else {
                    openSearch()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(showSearch ? PasteTheme.accent : .secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(showSearch ? PasteTheme.accent.opacity(0.14) : .clear)
                    )
            }
            .buttonStyle(.plain)
            .help(showSearch ? "收起搜索" : "搜索")

            Button {
                ScreenshotService.shared.capture(.region)
            } label: {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("截图（\(appState.screenshotHotkeyDisplay)）— 结果自动存入历史")

            boardTab(
                title: "剪贴板",
                systemImage: "clock.arrow.circlepath",
                selected: appState.panelViewMode == .shelf && appState.selectedAutoTag == nil,
                dot: Color.primary.opacity(0.45)
            ) {
                appState.panelViewMode = .shelf
                appState.selectedAutoTag = nil
                appState.selectedFilter = .all
                appState.showOnlyPinned = false
                appState.leaveFavorites()
            }

            boardTab(
                title: "收藏夹",
                systemImage: "star.fill",
                selected: appState.panelViewMode == .favorites,
                dot: Color(hex: "#F59E0B") ?? .orange,
                badge: favorites.isEmpty ? nil : favorites.count
            ) {
                appState.panelViewMode = .favorites
                appState.showFavorites(scope: .all)
            }

            boardTab(
                title: "时间线",
                systemImage: "calendar.day.timeline.leading",
                selected: appState.panelViewMode == .timeline,
                dot: Color(hex: "#EF4444") ?? .red
            ) {
                appState.panelViewMode = .timeline
                appState.leaveFavorites()
            }

            // Auto-tag boards styled like Paste collections
            ForEach(topTagCounts, id: \.0.id) { tag, count in
                boardTab(
                    title: "\(tag.displayName)",
                    systemImage: nil,
                    selected: appState.selectedAutoTag == tag.rawValue && appState.panelViewMode == .shelf,
                    dot: Color(hex: tag.accentHex) ?? PasteTheme.accent,
                    badge: count
                ) {
                    appState.panelViewMode = .shelf
                    appState.selectedFilter = .all
                    appState.showOnlyPinned = false
                    appState.leaveFavorites()
                    appState.selectedAutoTag = tag.rawValue
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isMonitoringEnabled ? Color.green.opacity(0.9) : Color.orange.opacity(0.9))
                    .frame(width: 6, height: 6)
                Text(appState.isMonitoringEnabled ? "后台监听中" : "已暂停")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(appState.hotkeyDisplay)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Menu {
                Button("粘贴选中项") { pasteSelected() }
                Divider()
                ForEach(ScreenshotMode.allCases) { mode in
                    Button(mode.title) { ScreenshotService.shared.capture(mode) }
                }
                Menu("截图识字（只存文字）") {
                    ForEach(ScreenshotMode.allCases) { mode in
                        Button(mode.title) { ScreenshotService.shared.capture(mode, recognizeText: true) }
                    }
                }
                Divider()
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
                Button("打开主窗口（\(appState.mainWindowHotkeyDisplay)）") {
                    StatusItemController.shared.showMainWindow()
                }
                Button("打开设置…") {
                    StatusItemController.shared.openSettings()
                }
                Button("隐藏面板") {
                    StatusItemController.shared.hidePanel()
                }
                Divider()
                Button("退出 PasteNest", role: .destructive) {
                    NSApp.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
        )
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    /// Floats above the nav bar as its own pill so the bar keeps its single-line layout.
    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            PanelSearchField(
                text: $draftQuery,
                placeholder: "搜索剪贴板…",
                shouldFocus: true,
                field: $searchField,
                onSubmit: pasteSelected
            )
            // The AppKit field has no natural size; without a fixed height it takes
            // every point the VStack offers and balloons into a giant capsule.
            .frame(maxWidth: .infinity)
            .frame(height: PanelSearchField.fieldHeight)
            .onChange(of: draftQuery) { _, value in
                scheduleSearch(value)
            }
            if !draftQuery.isEmpty {
                Text("\(filtered.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Button {
                if draftQuery.isEmpty {
                    closeSearch()
                } else {
                    clearSearch()
                }
            } label: {
                Image(systemName: draftQuery.isEmpty ? "xmark" : "xmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(draftQuery.isEmpty ? "收起搜索" : "清空")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        // One text line tall, whatever the window offers.
        .fixedSize(horizontal: false, vertical: true)
        .background {
            Capsule(style: .continuous)
                .fill(PasteTheme.panelFill.opacity(0.92))
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        }
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        // Keeps the pill's shadow off the window edge.
        .padding(.top, 8)
        // Fade only: a move transition can rest at its offset when the hosting view
        // is replaced mid-animation, which misplaced the pill.
        .transition(.opacity)
        .onAppear {
            // The panel rebuilds its hosting view on show / detail toggle; adopt the
            // live query so the field never disagrees with the filtered results.
            if draftQuery != appState.searchQuery {
                draftQuery = appState.searchQuery
            }
            focusSearchField()
        }
    }

    private func openSearch() {
        withAnimation(.easeOut(duration: 0.18)) {
            appState.isPanelSearchVisible = true
        }
        focusSearchField()
    }

    private func closeSearch() {
        searchField?.window?.makeFirstResponder(nil)
        withAnimation(.easeOut(duration: 0.18)) {
            appState.isPanelSearchVisible = false
        }
        clearSearch()
    }

    private func scheduleSearch(_ value: String) {
        searchDebounce?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            appState.searchQuery = ""
            return
        }
        let work = DispatchWorkItem {
            if appState.searchQuery != value {
                appState.searchQuery = value
            }
        }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }

    private func clearSearch() {
        searchDebounce?.cancel()
        draftQuery = ""
        appState.searchQuery = ""
    }

    private var topTagCounts: [(AutoTag, Int)] {
        var counts: [String: Int] = [:]
        for item in items {
            for tag in item.autoTags {
                counts[tag, default: 0] += 1
            }
        }
        return AutoTag.allCases.compactMap { tag in
            guard let count = counts[tag.rawValue], count > 0 else { return nil }
            return (tag, count)
        }
        .prefix(5)
        .map { $0 }
    }

    private func boardTab(
        title: String,
        systemImage: String?,
        selected: Bool,
        dot: Color,
        badge: Int? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { action() }
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                } else {
                    Circle()
                        .fill(dot)
                        .frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let badge {
                    Text("\(badge)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(selected ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var shelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // Lazy: the panel opens with only the visible cards built. The stack fills
            // the viewport height so the cards sit centered instead of hugging the top.
            LazyHStack(alignment: .center, spacing: 14) {
                if shouldShowLaunchCard {
                    onboardingCard(
                        icon: "power",
                        title: "登录时打开",
                        detail: "重启 Mac 后自动启动 PasteNest，保持常驻后台。",
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
                            onCopyText: { store?.copyText(item) },
                            onPin: { store?.togglePin(item) },
                            onDelete: { store?.delete(item) },
                            onToggleFavorite: { store?.toggleFavorite(item) },
                            availableTags: favorites.favoriteTagNames,
                            onToggleTag: { tag in store?.toggleFavoriteTag(tag, for: item) },
                            retentionDays: appState.keepUnfavoritedDays
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.top, 4)
            .frame(maxHeight: .infinity)
        }
    }

    private var shouldShowLaunchCard: Bool {
        !dismissLaunchCard && !appState.launchAtLogin
    }

    private var emptyCard: some View {
        let searching = !appState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(spacing: 10) {
            Image(systemName: searching ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(PasteTheme.accent)
            Text(searching ? "没有匹配「\(appState.searchQuery)」的内容" : "复制任意内容后会出现在这里")
                .font(.callout.weight(.medium))
            Text(searching ? "换个关键词，或试试更口语的说法" : "面板可随时关闭，App 继续在菜单栏后台运行")
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

/// Native AppKit field for the floating shelf.
///
/// SwiftUI `TextField` inside a non-activating `NSPanel` never reliably becomes
/// first responder — `@FocusState` is a no-op there, and walking the SwiftUI
/// hosting tree for an `NSTextField` misses the real editor (it sits beside the
/// background accessor, not above it). A representable `NSTextField` is the
/// field, so it can be made first responder and Chinese IME composes correctly.
private struct PanelSearchField: NSViewRepresentable {
    /// One line of 13pt system text plus the editor's insets.
    static let fieldHeight: CGFloat = 20

    @Binding var text: String
    var placeholder: String
    var shouldFocus: Bool
    @Binding var field: NSTextField?
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Flexible in width, one line tall — never let SwiftUI hand the field the
    /// whole remaining height of the panel.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PanelSearchFieldHost, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: Self.fieldHeight)
    }

    func makeNSView(context: Context) -> PanelSearchFieldHost {
        let host = PanelSearchFieldHost()
        host.textField.placeholderString = placeholder
        host.textField.stringValue = text
        host.textField.delegate = context.coordinator
        context.coordinator.host = host
        context.coordinator.text = $text
        context.coordinator.fieldRef = $field
        context.coordinator.onSubmit = onSubmit
        host.onAttachedToWindow = { [weak coordinator = context.coordinator] in
            DispatchQueue.main.async {
                coordinator?.publishField()
                coordinator?.focusIfNeeded()
            }
        }
        return host
    }

    func updateNSView(_ host: PanelSearchFieldHost, context: Context) {
        context.coordinator.text = $text
        context.coordinator.fieldRef = $field
        context.coordinator.onSubmit = onSubmit
        if host.textField.placeholderString != placeholder {
            host.textField.placeholderString = placeholder
        }
        // Never overwrite the field editor while the user is composing (IME).
        // The clear button is the one external edit that must land mid-edit.
        let editing = host.textField.currentEditor() != nil
        if editing {
            if text.isEmpty, !host.textField.stringValue.isEmpty {
                host.textField.stringValue = ""
            }
        } else if host.textField.stringValue != text {
            host.textField.stringValue = text
        }
        DispatchQueue.main.async {
            context.coordinator.publishField()
        }
        if shouldFocus {
            context.coordinator.focusIfNeeded()
        } else {
            context.coordinator.didFocus = false
        }
    }

    /// Makes the shelf key and the field first responder. Safe to call before
    /// the representable has a window — it no-ops until `viewDidMoveToWindow`.
    static func focus(_ field: NSTextField?) {
        guard let field, let window = field.window else { return }
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }
        if window.firstResponder !== field.currentEditor() {
            window.makeFirstResponder(field)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String> = .constant("")
        var fieldRef: Binding<NSTextField?> = .constant(nil)
        var onSubmit: () -> Void = {}
        weak var host: PanelSearchFieldHost?
        var didFocus = false

        func publishField() {
            fieldRef.wrappedValue = host?.textField
        }

        func focusIfNeeded() {
            guard !didFocus, let field = host?.textField, field.window != nil else { return }
            PanelSearchField.focus(field)
            if field.currentEditor() != nil {
                didFocus = true
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            if text.wrappedValue != field.stringValue {
                text.wrappedValue = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                onSubmit()
                return true
            }
            return false
        }
    }
}

/// Fills the SwiftUI slot so clicks land on the text field instead of dragging
/// the borderless panel (`isMovableByWindowBackground`).
private final class PanelSearchFieldHost: NSView {
    let textField = PanelSearchTextField()
    var onAttachedToWindow: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byClipping
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.cell?.usesSingleLineMode = true
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(textField)
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: PanelSearchField.fieldHeight)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? textField : nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            onAttachedToWindow?()
        }
    }
}

private final class PanelSearchTextField: NSTextField {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: PanelSearchField.fieldHeight)
    }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            editor.isContinuousSpellCheckingEnabled = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
        }
        return ok
    }
}

struct ClipboardItemDetailOverlay: View {
    let item: ClipboardItem
    var retentionDays: Int = RetentionPolicy.defaultDays
    let onClose: () -> Void
    let onCopy: () -> Void
    let onCopyText: () -> Void
    let onPaste: () -> Void
    var onToggleFavorite: (() -> Void)?

    /// Text recognized inside a screenshot, shown under the picture.
    private var recognizedText: String? {
        guard item.contentType == .image,
              let text = item.plainText,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    var body: some View {
        // Opaque full-panel surface — no shelf/timeline layer behind it.
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(PasteTheme.panelFill.opacity(0.96))
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
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
                HStack(spacing: 6) {
                    if let source = item.sourceAppName {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(item.favoriteTags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                (Color(hex: FavoriteTagCatalog.accentHex(for: tag)) ?? PasteTheme.accent).opacity(0.16),
                                in: Capsule()
                            )
                            .foregroundStyle(Color(hex: FavoriteTagCatalog.accentHex(for: tag)) ?? PasteTheme.accent)
                    }
                }
            }

            Spacer()

            if let onToggleFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(item.isFavorite ? Color(hex: "#F59E0B") ?? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.isFavorite ? "从收藏夹移除" : "收藏，长期保存")
            }

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
            VStack(alignment: .leading, spacing: 14) {
                if let image = ImageCache.shared.image(for: item, preferThumbnail: false) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Text("无法预览图片")
                        .foregroundStyle(.secondary)
                }
                if let recognizedText {
                    recognizedTextSection(recognizedText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func recognizedTextSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("识别到的文字", systemImage: "text.viewfinder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(TextRecognizer.characterCount(of: text)) 字")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Button(action: onCopyText) {
                    Label("复制文字", systemImage: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(text)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var detailFooter: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(
                    item.retentionStatus(days: retentionDays),
                    systemImage: item.isRetentionProtected ? "star.fill" : "clock"
                )
                .font(.caption2)
                .foregroundStyle(item.isRetentionProtected ? Color(hex: "#F59E0B") ?? .orange : Color.secondary)
            }
            Spacer()
            if recognizedText != nil {
                Button(action: onCopyText) {
                    Label("复制文字", systemImage: "text.viewfinder")
                }
                .buttonStyle(.bordered)
            }
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
    let onCopyText: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    var onToggleFavorite: (() -> Void)?
    /// Categories already in use across the folder, offered by the 分类 menu.
    var availableTags: [String] = []
    var onToggleTag: ((String) -> Void)?
    var retentionDays: Int = RetentionPolicy.defaultDays

    @State private var isHovered = false

    /// Only screenshots carry text on an image item.
    private var hasRecognizedText: Bool {
        item.contentType == .image && !(item.plainText ?? "").isEmpty
    }

    private var tagMenuOptions: [String] {
        let known = availableTags + item.favoriteTags
        return FavoriteTagCatalog.sanitizedMenuOptions(
            known: known,
            suggestions: FavoriteTagCatalog.unusedSuggestions(existing: known)
        )
    }

    private let cardWidth: CGFloat = 176
    private let cardHeight: CGFloat = 236
    private let previewHeight: CGFloat = 132

    private var characterCount: Int {
        item.plainText?.count ?? item.previewTitle.count
    }

    private var imagePixelSize: String? {
        ImageCache.shared.pixelSize(for: item)
    }

    private var footerMeta: String {
        if let imagePixelSize { return imagePixelSize }
        return "\(characterCount) 个字符"
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                cardHeader
                previewArea
                cardFooter
            }
            .frame(width: cardWidth, height: cardHeight)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? PasteTheme.cardHeader : (isHovered ? PasteTheme.cardBorder : PasteTheme.cardBorder.opacity(0.7)),
                        lineWidth: isSelected ? 2.5 : 1
                    )
            )
            .shadow(color: isSelected ? PasteTheme.cardHeader.opacity(0.22) : .black.opacity(0.06), radius: isSelected ? 10 : 4, y: 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onOpenDetail() })
        .contextMenu {
            Button("查看详情", action: onOpenDetail)
            Button("粘贴", action: onPaste)
            if hasRecognizedText {
                Button("复制识别的文字", action: onCopyText)
            }
            if let onToggleFavorite {
                Button(item.isFavorite ? "从收藏夹移除" : "收藏（长期保存）", action: onToggleFavorite)
            }
            if let onToggleTag {
                Menu("分类") {
                    ForEach(tagMenuOptions, id: \.self) { tag in
                        Button {
                            onToggleTag(tag)
                        } label: {
                            Label(
                                tag,
                                systemImage: FavoriteTagCatalog.contains(tag, in: item.favoriteTags)
                                ? "checkmark.circle.fill"
                                : "circle"
                            )
                        }
                    }
                }
            }
            Button(item.isPinned ? "取消置顶" : "置顶", action: onPin)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
        .scaleEffect(isSelected ? 1.015 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isSelected)
    }

    private var cardHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.contentType.displayName)
                    .font(.caption.weight(.bold))
                Text(item.updatedAt, style: .relative)
                    .font(.caption2)
                    .opacity(0.85)
            }
            Spacer(minLength: 4)
            if let onToggleFavorite, isHovered || isSelected || item.isFavorite {
                Button(action: onToggleFavorite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(item.isFavorite ? Color(hex: "#F59E0B") ?? .yellow : .white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help(item.isFavorite ? "从收藏夹移除" : "收藏，长期保存")
            }
            sourceAppIcon
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(PasteTheme.cardHeader)
    }

    private var previewArea: some View {
        ZStack(alignment: .topTrailing) {
            Color.white
            previewBody
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if hasRecognizedText {
                Label("文字", systemImage: "text.viewfinder")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(6)
            }
            if !item.favoriteTags.isEmpty {
                tagOverlay
            }
        }
        .frame(height: previewHeight)
        .clipped()
    }

    /// The categories this favorite carries, so the folder reads at a glance.
    private var tagOverlay: some View {
        HStack(spacing: 4) {
            ForEach(item.favoriteTags.prefix(2), id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (Color(hex: FavoriteTagCatalog.accentHex(for: tag)) ?? PasteTheme.accent).opacity(0.16),
                        in: Capsule()
                    )
                    .foregroundStyle(Color(hex: FavoriteTagCatalog.accentHex(for: tag)) ?? PasteTheme.accent)
            }
            if item.favoriteTags.count > 2 {
                Text("+\(item.favoriteTags.count - 2)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }

    private var cardFooter: some View {
        HStack(spacing: 6) {
            Text(footerMeta)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if item.isExpiringSoon(days: retentionDays) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(Color(hex: "#EE6C4D") ?? .orange)
                    .help("未收藏，不到 1 天后自动清理")
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(PasteTheme.cardHeader)
            }
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("\(index)")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var previewBody: some View {
        if item.contentType == .image, let nsImage = ImageCache.shared.image(for: item) {
            // Fit inside the card — never overflow the panel/card bounds.
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    CheckerboardBackground()
                        .opacity(0.35)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .clipped()
        } else if item.contentType == .color, let hex = item.colorHex {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: hex) ?? .gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomLeading) {
                    Text(hex)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white)
                        .padding(8)
                }
        } else {
            Text(item.plainText ?? item.previewTitle)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(7)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var sourceAppIcon: some View {
        if let icon = ImageCache.shared.sourceIcon(bundleID: item.sourceAppBundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else if let name = item.sourceAppName, !name.isEmpty {
            Image(systemName: "app.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .help(name)
        } else {
            Image(systemName: item.contentType.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
        }
    }
}

/// Subtle checkerboard behind transparent / fitted images (Paste-style).
private struct CheckerboardBackground: View {
    var cell: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for col in 0..<cols {
                    let light = (row + col) % 2 == 0
                    let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                    context.fill(
                        Path(rect),
                        with: .color(light ? Color.gray.opacity(0.18) : Color.gray.opacity(0.08))
                    )
                }
            }
        }
    }
}
