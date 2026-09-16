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
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(PasteTheme.accent)
                Text(appState.searchQuery.isEmpty ? PanelL10n.timelineEmpty : PanelL10n.timelineEmptySearch)
                    .font(PasteTheme.Typography.emptyTitle)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                Text(appState.searchQuery.isEmpty ? PanelL10n.timelineEmptyDetail : PanelL10n.timelineEmptySearchDetail)
                    .font(PasteTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
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
                                        onDelete: { store?.delete(item) },
                                        onToggleFavorite: { store?.toggleFavorite(item) }
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
                .font(PasteTheme.Typography.captionBold)
                .foregroundStyle(PasteTheme.accent)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
            Text("\(count)")
                .font(PasteTheme.Typography.chipBadge)
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
    var onToggleFavorite: (() -> Void)?

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
                                .font(PasteTheme.Typography.statusMono)
                                .foregroundStyle(.tertiary)
                            if item.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(PasteTheme.Typography.iconSmall)
                                    .foregroundStyle(PasteTheme.accent)
                            }
                            if item.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(PasteTheme.Typography.iconSmall)
                                    .foregroundStyle(Color(hex: "#F59E0B") ?? .orange)
                            }
                            Spacer()
                            if let tag = item.primaryAutoTag {
                                Text(tag.displayName)
                                    .font(PasteTheme.Typography.captionBold)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
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
                            .font(PasteTheme.Typography.bodyEmphasis)
                            .tracking(PasteTheme.Typography.tracking(for: item.previewTitle))
                            .lineSpacing(PasteTheme.Typography.lineSpacing(for: item.previewTitle))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)
                            .multilineTextAlignment(.leading)
                        if let sub = item.previewSubtitle ?? item.sourceAppName {
                            Text(sub)
                                .font(PasteTheme.Typography.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    if isHovered || isSelected {
                        HStack(spacing: 4) {
                            smallAction("return", onPaste)
                            if let onToggleFavorite {
                                smallAction(item.isFavorite ? "star.fill" : "star", onToggleFavorite)
                            }
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
                Button(PanelL10n.details, action: onOpenDetail)
                Button(PanelL10n.paste, action: onPaste)
                if let onToggleFavorite {
                    Button(item.isFavorite ? PanelL10n.unfavorite : PanelL10n.favorite, action: onToggleFavorite)
                }
                Button(item.isPinned ? PanelL10n.unpin : PanelL10n.pin, action: onPin)
                Divider()
                Button(PanelL10n.delete, role: .destructive, action: onDelete)
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
                .font(PasteTheme.Typography.icon)
                .foregroundStyle(Color(hex: tag?.accentHex ?? item.contentType.accentHex) ?? PasteTheme.accent)
        }
    }

    private func smallAction(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(PasteTheme.Typography.iconSmall)
                .frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

enum TimelineGrouper {
    /// Grouping sorts and buckets the whole list, so the result is memoized by a
    /// fingerprint of the inputs instead of recomputed on every body evaluation.
    private static var cachedFingerprint: Int?
    private static var cachedSections: [TimelineSection] = []

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    static func sections(from items: [ClipboardItem]) -> [TimelineSection] {
        var hasher = Hasher()
        hasher.combine(PanelL10n.language.rawValue)
        hasher.combine(items.count)
        for item in items {
            hasher.combine(item.id)
            hasher.combine(item.updatedAt)
        }
        let fingerprint = hasher.finalize()
        if fingerprint == cachedFingerprint {
            return cachedSections
        }

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
        let sections = buckets.map { TimelineSection(id: $0.0, title: $0.1, items: $0.2) }
        cachedFingerprint = fingerprint
        cachedSections = sections
        return sections
    }

    private static func sectionTitle(for day: Date, calendar: Calendar) -> String {
        weekdayFormatter.locale = PanelL10n.locale
        dayFormatter.locale = PanelL10n.locale
        dayFormatter.dateFormat = PanelL10n.dayFormat
        if calendar.isDateInToday(day) { return PanelL10n.today }
        if calendar.isDateInYesterday(day) { return PanelL10n.yesterday }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)),
           day >= weekAgo {
            return weekdayFormatter.string(from: day)
        }
        return dayFormatter.string(from: day)
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
                tagChip(title: PanelL10n.all, systemImage: "square.stack.3d.up", count: items.count, tagRaw: nil)

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
                    .font(PasteTheme.Typography.iconSmall)
                Text(title)
                    .font(compact ? PasteTheme.Typography.caption : PasteTheme.Typography.chip)
                    .tracking(PasteTheme.Typography.chipTracking)
                    .lineLimit(1)
                    .minimumScaleFactor(PasteTheme.Typography.chipMinimumScale)
                    .allowsTightening(true)
                Text("\(count)")
                    .font(PasteTheme.Typography.chipBadge)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, compact ? 8 : PasteTheme.Typography.chipHorizontalPadding)
            .padding(.vertical, compact ? 4 : PasteTheme.Typography.chipVerticalPadding)
            .background(
                selected ? accent.opacity(0.16) : Color.primary.opacity(0.05),
                in: Capsule()
            )
            .foregroundStyle(selected ? accent : .secondary)
        }
        .buttonStyle(.plain)
    }
}
