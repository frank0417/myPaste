import SwiftUI
import SwiftData

struct ClipboardHistoryPane: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \ClipboardItem.updatedAt, order: .reverse) private var items: [ClipboardItem]
    var store: ClipboardStore?

    private var filtered: [ClipboardItem] {
        items.filter { item in
            if appState.selectedFilter == .pinned || appState.showOnlyPinned {
                guard item.isPinned else { return false }
            } else if appState.selectedFilter != .all {
                switch appState.selectedFilter {
                case .text:
                    guard [.text, .richText, .snippet].contains(item.contentType) else { return false }
                case .link:
                    guard item.contentType == .link else { return false }
                case .image:
                    guard item.contentType == .image else { return false }
                case .file:
                    guard item.contentType == .file else { return false }
                case .code:
                    guard item.contentType == .code else { return false }
                case .all, .pinned:
                    break
                }
            }

            let q = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty else { return true }
            let haystack = [
                item.previewTitle,
                item.previewSubtitle,
                item.plainText,
                item.sourceAppName
            ].compactMap { $0?.lowercased() }.joined(separator: " ")
            return haystack.contains(q.lowercased())
        }
    }

    private var pinned: [ClipboardItem] { filtered.filter(\.isPinned) }
    private var recent: [ClipboardItem] { filtered.filter { !$0.isPinned } }

    var body: some View {
        VStack(spacing: 0) {
            FilterChipBar()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            if filtered.isEmpty {
                EmptyHistoryView(hasSearch: !appState.searchQuery.isEmpty)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !pinned.isEmpty {
                            sectionHeader("置顶")
                            ForEach(pinned) { item in
                                ClipboardItemRow(
                                    item: item,
                                    isSelected: appState.selectedItemID == item.id
                                ) {
                                    appState.selectedItemID = item.id
                                } onPaste: {
                                    store?.paste(item)
                                } onPin: {
                                    store?.togglePin(item)
                                } onDelete: {
                                    store?.delete(item)
                                }
                            }
                        }

                        if !recent.isEmpty {
                            sectionHeader("最近复制")
                            ForEach(recent) { item in
                                ClipboardItemRow(
                                    item: item,
                                    isSelected: appState.selectedItemID == item.id
                                ) {
                                    appState.selectedItemID = item.id
                                } onPaste: {
                                    store?.paste(item)
                                } onPin: {
                                    store?.togglePin(item)
                                } onDelete: {
                                    store?.delete(item)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color.clear)
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
            Text(hasSearch ? "没有匹配的结果" : "开始复制吧")
                .font(.title3.weight(.semibold))
            Text(hasSearch ? "试试其他关键词，或切换内容类型筛选。" : "复制的文本、链接、图片与文件会出现在这里，并可跨设备同步。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
