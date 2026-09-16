import SwiftUI
import SwiftData

struct ClipboardHistoryPane: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \ClipboardItem.updatedAt, order: .reverse) private var items: [ClipboardItem]
    var store: ClipboardStore?

    private var filtered: [ClipboardItem] {
        var hasher = Hasher()
        hasher.combine(appState.searchQuery)
        hasher.combine(appState.selectedFilter.rawValue)
        hasher.combine(appState.showOnlyPinned)
        hasher.combine(appState.showOnlyFavorites)
        hasher.combine(appState.favoriteScope)
        hasher.combine(appState.selectedAutoTag)
        hasher.combine(appState.embeddingRevision)
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
        let value = ClipboardItemFilter.filter(items, appState: appState)
        filterMemo.key = key
        filterMemo.value = value
        return value
    }

    @State private var filterMemo = FilterMemo()

    private var pinned: [ClipboardItem] { filtered.filter(\.isPinned) }
    private var recent: [ClipboardItem] { filtered.filter { !$0.isPinned } }
    private var favorites: [ClipboardItem] { items.filter(\.isFavorite) }

    var body: some View {
        VStack(spacing: 0) {
            historyModeBar
            if appState.mainHistoryMode == .favorites {
                // The folder brings its own category chips and empty state.
                FavoritesFolderView(
                    items: filtered,
                    favorites: favorites,
                    layout: .grid,
                    store: store,
                    // The preview pane is always on screen here, so a double click
                    // pastes like it does on the list rows.
                    onOpenDetail: { store?.paste($0) }
                )
            } else {
                AutoTagFilterBar(items: items)
                FilterChipBar()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                if filtered.isEmpty {
                    EmptyHistoryView(hasSearch: !appState.searchQuery.isEmpty)
                } else if appState.mainHistoryMode == .timeline {
                    TimelineOutlineView(items: filtered, store: store)
                } else {
                    listContent
                }
            }
        }
        .onChange(of: appState.showOnlyFavorites) { _, only in
            // The shelf panel shares this filter; follow it so the list never silently
            // shows favorites only, without the folder's category chips.
            if only, appState.mainHistoryMode != .favorites {
                appState.mainHistoryMode = .favorites
            } else if !only, appState.mainHistoryMode == .favorites {
                appState.mainHistoryMode = .list
            }
        }
        .onAppear {
            EmbeddingIndex.shared.backfill(items.prefix(300).map { ($0.id, $0.searchableText) })
        }
    }

    private var historyModeBar: some View {
        HStack(spacing: 8) {
            modeButton(title: PanelL10n.list, systemImage: "list.bullet", mode: .list)
            modeButton(title: PanelL10n.timeline, systemImage: "calendar.day.timeline.leading", mode: .timeline)
            modeButton(title: PanelL10n.favorites, systemImage: "star.fill", mode: .favorites)
            Spacer()
            Text(PanelL10n.itemCount(filtered.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func modeButton(title: String, systemImage: String, mode: AppState.MainHistoryMode) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) {
                appState.mainHistoryMode = mode
                if mode == .favorites {
                    appState.showFavorites(scope: .all)
                } else {
                    appState.leaveFavorites()
                }
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    appState.mainHistoryMode == mode
                    ? PasteTheme.accent.opacity(0.14)
                    : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .foregroundStyle(appState.mainHistoryMode == mode ? PasteTheme.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var listContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !pinned.isEmpty {
                    sectionHeader(PanelL10n.pin)
                    ForEach(pinned) { item in
                        historyRow(item)
                    }
                }
                if !recent.isEmpty {
                    sectionHeader(PanelL10n.recentlyCopied)
                    ForEach(recent) { item in
                        historyRow(item)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func historyRow(_ item: ClipboardItem) -> some View {
        ClipboardItemRow(
            item: item,
            isSelected: appState.selectedItemID == item.id,
            onSelect: { appState.selectedItemID = item.id },
            onPaste: { store?.paste(item) },
            onPin: { store?.togglePin(item) },
            onDelete: { store?.delete(item) },
            onToggleFavorite: { store?.toggleFavorite(item) },
            retentionDays: appState.keepUnfavoritedDays
        )
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

struct FilterChipBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AppState.ContentFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appState.selectedFilter = filter
                            appState.showOnlyPinned = filter == .pinned
                            if filter == .favorite {
                                appState.mainHistoryMode = .favorites
                                appState.showFavorites(scope: .all)
                            } else {
                                appState.leaveFavorites()
                            }
                            if filter != .all {
                                appState.selectedAutoTag = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.systemImage)
                                .font(.caption)
                            Text(filter.title)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            appState.selectedFilter == filter
                            ? PasteTheme.accent.opacity(0.16)
                            : Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                        .foregroundStyle(
                            appState.selectedFilter == filter ? PasteTheme.accent : .secondary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct EmptyHistoryView: View {
    let hasSearch: Bool

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: hasSearch ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(PasteTheme.accent.opacity(0.7))
                .symbolEffect(.pulse, options: .repeating)
            Text(hasSearch ? PanelL10n.emptyHistorySearch : PanelL10n.startCopying)
                .font(.title3.weight(.semibold))
            Text(hasSearch ? PanelL10n.emptyHistorySearchDetail : PanelL10n.emptyHistoryDetail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
