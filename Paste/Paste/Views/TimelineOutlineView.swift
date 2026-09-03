import SwiftUI
import SwiftData

struct TimelineSection: Identifiable {
    let id: String
    let title: String
    let items: [ClipboardItem]
}

struct TimelineOutlineView: View {
    @EnvironmentObject private var appState: AppState
    let items: [ClipboardItem]
    var store: ClipboardStore?
    var onOpenDetail: ((ClipboardItem) -> Void)?

    private var sections: [TimelineSection] {
        TimelineGrouper.sections(from: items)
    }

    var body: some View {
        if items.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: appState.searchQuery.isEmpty ? "calendar.day.timeline.leading" : "magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(PasteTheme.accent)
                Text(appState.searchQuery.isEmpty ? "时间线为空" : "无匹配记录")
                    .font(.callout.weight(.medium))
                Text(appState.searchQuery.isEmpty ? "复制内容后会按日期出现在这里" : "试试其他关键词或切换标签")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.items) { item in
                                    TimelineOutlineRow(
                                        item: item,
                                        isSelected: appState.selectedItemID == item.id,
                                        onSelect: { appState.selectedItemID = item.id },
                                        onOpenDetail: { onOpenDetail?(item) },
                                        onPaste: { store?.paste(item) },
                                        onPin: { store?.togglePin(item) },
                                        onDelete: { store?.delete(item) }
                                    )
                                    .id(item.id)
                                }
                            } header: {
                                timelineSectionHeader(section.title, count: section.items.count)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
                .onChange(of: appState.selectedItemID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func timelineSectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(PasteTheme.accent)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
            Text("\(count)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

struct TimelineOutlineRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpenDetail: () -> Void
    let onPaste: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(isSelected ? PasteTheme.accent : Color.primary.opacity(0.2))
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)

            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 10) {
                    typeIcon
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.updatedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                            if item.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.caption2)
                                    .foregroundStyle(PasteTheme.accent)
                            }
                            Spacer()
                            if let tag = item.primaryAutoTag {
                                Text(tag.displayName)
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        (Color(hex: tag.accentHex) ?? PasteTheme.accent).opacity(0.12),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(Color(hex: tag.accentHex) ?? PasteTheme.accent)
                            }
                        }
                        Text(item.previewTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let sub = item.previewSubtitle ?? item.sourceAppName {
                            Text(sub)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if isHovered || isSelected {
                        HStack(spacing: 4) {
                            smallAction("return", onPaste)
                            smallAction("pin", onPin)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? PasteTheme.accent.opacity(0.1) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .simultaneousGesture(TapGesture(count: 2).onEnded { onOpenDetail() })
            .contextMenu {
                Button("查看详情", action: onOpenDetail)
                Button("粘贴", action: onPaste)
                Button(item.isPinned ? "取消置顶" : "置顶", action: onPin)
                Divider()
                Button("删除", role: .destructive, action: onDelete)
            }
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var typeIcon: some View {
        let tag = item.primaryAutoTag
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill((Color(hex: tag?.accentHex ?? item.contentType.accentHex) ?? PasteTheme.accent).opacity(0.14))
                .frame(width: 32, height: 32)
            Image(systemName: tag?.systemImage ?? item.contentType.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: tag?.accentHex ?? item.contentType.accentHex) ?? PasteTheme.accent)
        }
    }

    private func smallAction(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

enum TimelineGrouper {
    static func sections(from items: [ClipboardItem]) -> [TimelineSection] {
        let calendar = Calendar.current
        let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
        var buckets: [(String, String, [ClipboardItem])] = []
        var lookup: [String: Int] = [:]

        for item in sorted {
            let day = calendar.startOfDay(for: item.updatedAt)
            let key = day.timeIntervalSince1970.description
            let title = sectionTitle(for: day, calendar: calendar)
            if let idx = lookup[key] {
                buckets[idx].2.append(item)
            } else {
                lookup[key] = buckets.count
                buckets.append((key, title, [item]))
            }
        }
        return buckets.map { TimelineSection(id: $0.0, title: $0.1, items: $0.2) }
    }

    private static func sectionTitle(for day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "今天" }
        if calendar.isDateInYesterday(day) { return "昨天" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)),
           day >= weekAgo {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh-Hans")
            formatter.dateFormat = "EEEE"
            return formatter.string(from: day)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh-Hans")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: day)
    }
}

struct AutoTagFilterBar: View {
    @EnvironmentObject private var appState: AppState
    let items: [ClipboardItem]
    var compact: Bool = false

    private var tagCounts: [(AutoTag, Int)] {
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
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: compact ? 6 : 8) {
                tagChip(title: "全部", systemImage: "square.stack.3d.up", count: items.count, tagRaw: nil)

                ForEach(tagCounts, id: \.0.id) { tag, count in
                    tagChip(
                        title: tag.displayName,
                        systemImage: tag.systemImage,
                        count: count,
                        tagRaw: tag.rawValue,
                        accent: Color(hex: tag.accentHex) ?? PasteTheme.accent
                    )
                }
            }
            .padding(.horizontal, compact ? 14 : 16)
        }
        .padding(.vertical, compact ? 4 : 6)
    }

    private func tagChip(
        title: String,
        systemImage: String,
        count: Int,
        tagRaw: String?,
        accent: Color = PasteTheme.accent
    ) -> some View {
        let selected = appState.selectedAutoTag == tagRaw
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                appState.selectedFilter = .all
                appState.showOnlyPinned = false
                appState.selectedAutoTag = tagRaw
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2)
                Text(title)
                    .font(compact ? .caption2.weight(.medium) : .caption.weight(.medium))
                Text("\(count)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 6)
            .background(
                selected ? accent.opacity(0.16) : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .foregroundStyle(selected ? accent : .secondary)
        }
        .buttonStyle(.plain)
    }
}
