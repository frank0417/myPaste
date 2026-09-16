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
            retentionDays: appState.keepUnfavoritedDays
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: searching ? "magnifyingglass" : "star")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(PasteTheme.accent)
            Text(emptyTitle)
                .font(.callout.weight(.medium))
            Text(emptyDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
        if searching { return "收藏夹里没有匹配的内容" }
        switch appState.favoriteScope {
        case .all: return "收藏夹还是空的"
        case .untagged: return "所有收藏都已分类"
        case .tag(let name): return "「\(name)」分类下还没有内容"
        }
    }

    private var emptyDetail: String {
        if searching { return "换个关键词，或切回「全部收藏」" }
        switch appState.favoriteScope {
        case .all:
            return "收藏的内容长期保存；未收藏的只保留 \(appState.keepUnfavoritedDays) 天。右键任意卡片选择「收藏」即可放进来。"
        case .untagged:
            return "右键收藏卡片 →「分类」可以随时调整标签。"
        case .tag:
            return "右键收藏卡片 →「分类」把内容打上这个标签。"
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
                    title: "全部收藏",
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
                        Button("删除分类「\(tag.name)」", role: .destructive) {
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
                        Label("分类", systemImage: "plus")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("新建分类并应用到选中的收藏")
                }
            }
            .padding(.horizontal, compact ? 14 : 16)
        }
        .padding(.vertical, compact ? 5 : 7)
    }

    private var newTagField: some View {
        HStack(spacing: 6) {
            Image(systemName: "tag")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(targetItem == nil ? "先选中一条收藏" : "分类名称，回车确认", text: $draftTag)
                .textFieldStyle(.plain)
                .font(.caption)
                .frame(width: 130)
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
                    .font(.caption2)
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text("\(count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                selected ? accent.opacity(0.16) : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .foregroundStyle(selected ? accent : .secondary)
        }
        .buttonStyle(.plain)
    }
}
