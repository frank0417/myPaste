import SwiftUI
import AppKit

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    var onToggleFavorite: (() -> Void)?
    var retentionDays: Int = RetentionPolicy.defaultDays

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                typeBadge
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.previewTitle)
                        .font(.system(.body, design: .default).weight(.medium))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        if item.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(PasteTheme.accent)
                        }
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(Color(hex: "#F59E0B") ?? .orange)
                        }
                        ForEach(item.favoriteTags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    (Color(hex: FavoriteTagCatalog.accentHex(for: tag)) ?? PasteTheme.accent).opacity(0.16),
                                    in: Capsule()
                                )
                                .foregroundStyle(Color(hex: FavoriteTagCatalog.accentHex(for: tag)) ?? PasteTheme.accent)
                        }
                        if item.isExpiringSoon(days: retentionDays) {
                            Image(systemName: "clock.badge.exclamationmark")
                                .font(.caption2)
                                .foregroundStyle(Color(hex: "#EE6C4D") ?? .orange)
                                .help(PanelL10n.expiringSoonHelp)
                        }
                        Text(item.previewSubtitle ?? item.contentType.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(item.updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if isHovered || isSelected {
                    HStack(spacing: 4) {
                        if let onToggleFavorite {
                            iconButton(item.isFavorite ? "star.fill" : "star", action: onToggleFavorite)
                        }
                        iconButton("pin", action: onPin)
                        iconButton("return", action: onPaste)
                        iconButton("trash", action: onDelete)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? PasteTheme.accent.opacity(0.45) : Color.primary.opacity(0.04),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .contextMenu {
            Button(PanelL10n.paste, action: onPaste)
            if let onToggleFavorite {
                Button(item.isFavorite ? PanelL10n.unfavorite : PanelL10n.favorite, action: onToggleFavorite)
            }
            Button(item.isPinned ? PanelL10n.unpin : PanelL10n.pin, action: onPin)
            Divider()
            Button(PanelL10n.delete, role: .destructive, action: onDelete)
        }
        .onTapGesture(count: 2, perform: onPaste)
    }

    @ViewBuilder
    private var typeBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: item.contentType.accentHex)?.opacity(0.14) ?? PasteTheme.accent.opacity(0.14))
                .frame(width: 42, height: 42)
            if item.contentType == .image, let nsImage = ImageCache.shared.image(for: item) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if item.contentType == .color, let hex = item.colorHex {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 42, height: 42)
            } else {
                Image(systemName: item.contentType.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: item.contentType.accentHex) ?? PasteTheme.accent)
            }
        }
    }

    private var rowBackground: Color {
        if isSelected { return PasteTheme.accent.opacity(0.10) }
        if isHovered { return Color.primary.opacity(0.04) }
        return Color.primary.opacity(0.025)
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
