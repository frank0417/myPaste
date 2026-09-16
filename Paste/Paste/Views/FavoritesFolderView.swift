import SwiftUI
import SwiftData

/// The favorites folder: the only place items live indefinitely. Everything else is a
/// buffer that expires, so this view doubles as the explanation of that policy.
struct FavoritesFolderView: View {
    enum Layout {
        /// One horizontal row, for the bottom shelf panel.
        case shelf
        /// A wrapping grid, for the main window.
        case grid
    }

    @EnvironmentObject private var appState: AppState
    /// Already filtered by the active category and the search query.
    let items: [ClipboardItem]
    /// Every favorite, so the category chips can count the whole folder.
    let favorites: [ClipboardItem]
    var layout: Layout = .grid
    var store: ClipboardStore?
    var onOpenDetail: ((ClipboardItem) -> Void)?
    /// The shelf panel also hides itself after pasting.
    var onPaste: ((ClipboardItem) -> Void)?

    private var sorted: [ClipboardItem] {
        // A search hands us ranked results; otherwise the folder reads newest-kept first.
        guard appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return items
        }
        return items.sorted { lhs, rhs in
            (lhs.favoritedAt ?? lhs.updatedAt) > (rhs.favoritedAt ?? rhs.updatedAt)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FavoriteTagBar(favorites: favorites, compact: layout == .shelf, store: store)
            if sorted.isEmpty {
                emptyState
            } else if layout == .shelf {
                shelfContent
            } else {
                gridContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var shelfContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .center, spacing: 14) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, item in
                    card(item, index: index + 1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
            .padding(.top, 4)
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 176, maximum: 210), spacing: 14)],
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { index, item in
                    card(item, index: index + 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private func card(_ item: ClipboardItem, index: Int) -> some View {
        ClipboardShelfCard(
            item: item,
            index: index,
            isSelected: appState.selectedItemID == item.id,
            onSelect: { appState.selectedItemID = item.id },
            onOpenDetail: { onOpenDetail?(item) },
            onPaste: {
                if let onPaste {
                    onPaste(item)
                } else {
                    store?.paste(item)
                }
            },
            onCopyText: { store?.copyText(item) },
            onPin: { store?.togglePin(item) },
            onDelete: { store?.delete(item) },
            onToggleFavorite: { store?.toggleFavorite(item) },
            availableTags: favorites.favoriteTagNames,
            onToggleTag: { tag in store?.toggleFavoriteTag(tag, for: item) },
            onRecognizeText: { store?.recognizeText(in: item) },
            onSaveImage: { store?.saveImage(item) },
            retentionDays: appState.keepUnfavoritedDays
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: searching ? "magnifyingglass" : "star")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(PasteTheme.accent)
            Text(emptyTitle)
                .font(PasteTheme.Typography.emptyTitle)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
            Text(emptyDetail)
                .font(PasteTheme.Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: 320)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, layout == .shelf ? 18 : 0)
    }

    private var searching: Bool {
        !appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyTitle: String {
        if searching { return PanelL10n.favoritesEmptySearch }
        switch appState.favoriteScope {
        case .all: return PanelL10n.favoritesEmpty
        case .untagged: return PanelL10n.favoritesAllTagged
        case .tag(let name): return PanelL10n.favoritesEmptyTag(name)
        }
    }

    private var emptyDetail: String {
        if searching { return PanelL10n.favoritesEmptySearchDetail }
        switch appState.favoriteScope {
        case .all:
            return PanelL10n.favoritesEmptyDetail(appState.keepUnfavoritedDays)
        case .untagged:
            return PanelL10n.favoritesUntaggedDetail
        case .tag:
            return PanelL10n.favoritesTagDetail
        }
    }
}

/// Category chips for the folder, plus the inline field that creates a new one.
struct FavoriteTagBar: View {
    @EnvironmentObject private var appState: AppState
    let favorites: [ClipboardItem]
    var compact: Bool = false
    var store: ClipboardStore?

    @State private var isAddingTag = false
    @State private var draftTag = ""
    @FocusState private var tagFieldFocused: Bool

    private var counts: [FavoriteTagCount] { favorites.favoriteTagCounts }
    private var untaggedCount: Int { favorites.filter { $0.favoriteTags.isEmpty }.count }

    /// New categories are typed once and applied to the item in focus.
    private var targetItem: ClipboardItem? {
        guard let id = appState.selectedItemID else { return nil }
        return favorites.first { $0.id == id }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: compact ? 6 : 8) {
                chip(
                    title: PanelL10n.allFavorites,
                    systemImage: "star.fill",
                    count: favorites.count,
                    accent: PasteTheme.accent,
                    selected: appState.favoriteScope == .all
                ) {
                    appState.showFavorites(scope: .all)
                }

                ForEach(counts) { tag in
                    chip(
                        title: tag.name,
                        systemImage: "tag.fill",
                        count: tag.count,
                        accent: Color(hex: tag.accentHex) ?? PasteTheme.accent,
                        selected: appState.favoriteScope == .tag(tag.name)
                    ) {
                        appState.showFavorites(scope: .tag(tag.name))
                    }
                    .contextMenu {
                        Button(PanelL10n.deleteTag(tag.name), role: .destructive) {
                            store?.deleteFavoriteTag(tag.name)
                            if appState.favoriteScope == .tag(tag.name) {
                                appState.showFavorites(scope: .all)
                            }
                        }
                    }
                }

                if untaggedCount > 0 {
                    chip(
                        title: FavoriteTagCatalog.untaggedTitle,
                        systemImage: "tag",
                        count: untaggedCount,
                        accent: .secondary,
                        selected: appState.favoriteScope == .untagged
                    ) {
                        appState.showFavorites(scope: .untagged)
                    }
                }

                if isAddingTag {
                    newTagField
                } else {
                    Button {
                        isAddingTag = true
                        tagFieldFocused = true
                    } label: {
                        Label(PanelL10n.tag, systemImage: "plus")
                            .font(PasteTheme.Typography.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .padding(.horizontal, PasteTheme.Typography.chipHorizontalPadding)
                            .padding(.vertical, PasteTheme.Typography.chipVerticalPadding)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(PanelL10n.newTagHelp)
                }
            }
            .padding(.horizontal, compact ? 14 : 16)
        }
        .padding(.vertical, compact ? 5 : 7)
    }

    private var newTagField: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(PasteTheme.Typography.caption)
                .foregroundStyle(.secondary)
            TextField(targetItem == nil ? PanelL10n.pickFavoriteFirst : PanelL10n.tagPlaceholder, text: $draftTag)
                .textFieldStyle(.plain)
                .font(PasteTheme.Typography.caption)
                .frame(minWidth: 96, maxWidth: 168)
                .focused($tagFieldFocused)
                .disabled(targetItem == nil)
                .onSubmit(commitTag)
            Button {
                closeTagField()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }

    private func commitTag() {
        guard let item = targetItem, let name = FavoriteTagCatalog.normalize(draftTag) else {
            closeTagField()
            return
        }
        store?.addFavoriteTag(name, to: item)
        draftTag = ""
        isAddingTag = false
        tagFieldFocused = false
        appState.showFavorites(scope: .tag(name))
    }

    private func closeTagField() {
        draftTag = ""
        isAddingTag = false
        tagFieldFocused = false
    }

    private func chip(
        title: String,
        systemImage: String,
        count: Int,
        accent: Color,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { action() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(PasteTheme.Typography.iconSmall)
                Text(title)
                    .shelfChipLabel()
                Text("\(count)")
                    .font(PasteTheme.Typography.chipBadge)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, PasteTheme.Typography.chipHorizontalPadding)
            .padding(.vertical, PasteTheme.Typography.chipVerticalPadding)
            .background(
                selected ? accent.opacity(0.16) : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .foregroundStyle(selected ? accent : .secondary)
        }
        .buttonStyle(.plain)
    }
}
