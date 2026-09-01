import SwiftUI
import AppKit

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

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
            Button("粘贴", action: onPaste)
            Button(item.isPinned ? "取消置顶" : "置顶", action: onPin)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
        .onTapGesture(count: 2, perform: onPaste)
    }

    @ViewBuilder
    private var typeBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: item.contentType.accentHex)?.opacity(0.14) ?? PasteTheme.accent.opacity(0.14))
                .frame(width: 42, height: 42)
            if item.contentType == .image, let data = item.thumbnailData ?? item.imageData,
               let nsImage = NSImage(data: data) {
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
