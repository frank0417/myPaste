import SwiftUI
import SwiftData

struct ClipboardHistoryPane: View {
    @EnvironmentObject private var appState: AppState
    @Query(sort: \ClipboardItem.updatedAt, order: .reverse) private var items: [ClipboardItem]
    var store: ClipboardStore?

    private var filtered: [ClipboardItem] {
        ClipboardItemFilter.filter(items, appState: appState)
    }

    private var pinned: [ClipboardItem] { filtered.filter(\.isPinned) }
    private var recent: [ClipboardItem] { filtered.filter { !$0.isPinned } }

    var body: some View {
        VStack(spacing: 0) {
            historyModeBar
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

    private var historyModeBar: some View {
        HStack(spacing: 8) {
            modeButton(title: "列表", systemImage: "list.bullet", mode: .list)
            modeButton(title: "时间线", systemImage: "calendar.day.timeline.leading", mode: .timeline)
            Spacer()
            Text("\(filtered.count) 条")
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
                    sectionHeader("置顶")
                    ForEach(pinned) { item in
                        historyRow(item)
                    }
                }
                if !recent.isEmpty {
                    sectionHeader("最近复制")
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
            onDelete: { store?.delete(item) }
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
            Text(hasSearch ? "没有匹配的结果" : "开始复制吧")
                .font(.title3.weight(.semibold))
            Text(hasSearch ? "试试其他关键词，或切换标签 / 时间线筛选。" : "复制的文本、链接、图片与文件会自动打标签，并出现在时间线中。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
