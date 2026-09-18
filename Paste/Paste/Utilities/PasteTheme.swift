import SwiftUI
import AppKit

enum PasteTheme {
    static let accent = Color(hex: "#0F766E") ?? .teal
    static let cardHeader = Color(hex: "#2F6FED") ?? .blue
    static let cardBorder = Color(hex: "#D7DEE8") ?? .gray.opacity(0.35)
    static let ink = Color(hex: "#1B2A2F") ?? .primary
    static let mist = Color(hex: "#E8F1F0") ?? .gray.opacity(0.2)
    static let sand = Color(hex: "#F3EFE7") ?? .gray.opacity(0.15)
    static let coral = Color(hex: "#E07A5F") ?? .orange
    static let panelFill = Color(hex: "#F4F6F8") ?? Color(nsColor: .windowBackgroundColor)

    /// A single type ramp for the shelf. CJK sits a quarter-point larger than Latin
    /// at the same optical weight; Latin tightens tracking so longer English labels
    /// still fit the same chips. Clipboard previews pick spacing from the text itself.
    enum Typography {
        static var usesCJKLayout: Bool { PanelL10n.language != .en }

        static var icon: Font { .system(size: 12.5, weight: .semibold) }
        static var iconSmall: Font { .system(size: 11, weight: .semibold) }
        static var chip: Font {
            .system(size: usesCJKLayout ? 12 : 11.5, weight: .semibold)
        }
        static var chipBadge: Font { .system(size: 10, weight: .medium).monospacedDigit() }
        static var status: Font { .system(size: usesCJKLayout ? 11 : 10.5, weight: .medium) }
        static var statusMono: Font { .system(size: 10.5, weight: .medium, design: .monospaced) }
        static var caption: Font { .system(size: usesCJKLayout ? 11 : 10.5, weight: .medium) }
        static var captionBold: Font { .system(size: usesCJKLayout ? 11 : 10.5, weight: .semibold) }
        static var button: Font { .system(size: usesCJKLayout ? 12 : 11.5, weight: .semibold) }
        static var title: Font { .system(size: usesCJKLayout ? 15 : 14.5, weight: .semibold) }
        static var headline: Font { .system(size: usesCJKLayout ? 13.5 : 13, weight: .semibold) }
        static var emptyTitle: Font { .system(size: usesCJKLayout ? 13.5 : 13, weight: .medium) }
        static var preview: Font { .system(size: usesCJKLayout ? 12.5 : 12, weight: .regular) }
        static var previewMono: Font { .system(size: 12, weight: .regular, design: .monospaced) }
        static var body: Font { .system(size: usesCJKLayout ? 13 : 12.5, weight: .regular) }
        static var bodyEmphasis: Font { .system(size: usesCJKLayout ? 13 : 12.5, weight: .medium) }

        static var chipTracking: CGFloat { usesCJKLayout ? 0.15 : -0.2 }
        static var chipMinimumScale: CGFloat { usesCJKLayout ? 0.88 : 0.75 }
        /// CJK glyphs fill the em square, so capsules need a little more vertical room.
        static var chipHorizontalPadding: CGFloat { usesCJKLayout ? 10 : 9 }
        static var chipVerticalPadding: CGFloat { usesCJKLayout ? 6 : 5 }
        static var buttonHorizontalPadding: CGFloat { usesCJKLayout ? 12 : 10 }
        static var buttonVerticalPadding: CGFloat { usesCJKLayout ? 6.5 : 5 }
        static var actionGap: CGFloat { usesCJKLayout ? 4 : 5.5 }
        static var iconButtonSize: CGFloat { 24 }
        static var searchPointSize: CGFloat { usesCJKLayout ? 12.5 : 12 }

        static func containsCJK(_ text: String) -> Bool {
            text.contains(where: \.isCJK)
        }

        static func lineSpacing(for text: String) -> CGFloat {
            containsCJK(text) ? 3.5 : 1.5
        }

        static func tracking(for text: String) -> CGFloat {
            containsCJK(text) ? 0.1 : -0.15
        }
    }

    /// One corner language for the whole shelf: the window surface, the cards inside
    /// it, and the smaller controls step down together so nothing reads as a box.
    static let panelCornerRadius: CGFloat = 28
    static let cardCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 12

    static var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
    }

    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }

    static var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: controlCornerRadius, style: .continuous)
    }

    /// The bright shelf-card header, eased into a gradient so the block does not
    /// end in a flat wall of colour against the white preview.
    static var cardHeaderGradient: LinearGradient {
        LinearGradient(
            colors: [cardHeader, cardHeader.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "#F7F4EE") ?? .white,
                Color(hex: "#E7F0EF") ?? .white,
                Color(hex: "#F0EBE3") ?? .white
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init?(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }

        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let a, r, g, b: Double
        if cleaned.count == 8 {
            a = Double((value & 0xFF000000) >> 24) / 255
            r = Double((value & 0x00FF0000) >> 16) / 255
            g = Double((value & 0x0000FF00) >> 8) / 255
            b = Double(value & 0x000000FF) / 255
        } else {
            a = 1
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

extension View {
    /// The floating shelf's surface. Frosted material under a soft tint, edged by a
    /// hairline shade outside and a hairline highlight just inside it, so the rounded
    /// corners fade into whatever is behind the window instead of ending in a hard cut.
    /// The window itself is transparent and draws no shadow: anything the window
    /// bounds would clip shows up as a frame around the panel.
    func panelSurface() -> some View {
        self
            .background {
                PasteTheme.panelShape
                    .fill(.ultraThinMaterial)
                    .overlay(PasteTheme.panelShape.fill(PasteTheme.panelFill.opacity(0.86)))
            }
            .clipShape(PasteTheme.panelShape)
            .overlay {
                PasteTheme.panelShape
                    .inset(by: 1)
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                PasteTheme.panelShape
                    .strokeBorder(Color.black.opacity(0.09), lineWidth: 1)
                    .allowsHitTesting(false)
            }
    }

    /// A control pill inside the shelf: a soft white capsule with a hairline edge in
    /// place of a drop shadow, so it sits in the surface rather than on top of it.
    func shelfPill(tint: Color = .clear) -> some View {
        self
            .background(
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint == .clear ? Color.primary.opacity(0.06) : tint, lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }

    func pasteCard() -> some View {
        self
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }

    /// Chip / tab labels: one line, slight tracking, shrinks for long English words.
    func shelfChipLabel() -> some View {
        self
            .font(PasteTheme.Typography.chip)
            .tracking(PasteTheme.Typography.chipTracking)
            .lineLimit(1)
            .minimumScaleFactor(PasteTheme.Typography.chipMinimumScale)
            .allowsTightening(true)
    }

    func shelfCaption() -> some View {
        self
            .font(PasteTheme.Typography.caption)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .allowsTightening(true)
    }

    func shelfStatusLabel() -> some View {
        self
            .font(PasteTheme.Typography.status)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .allowsTightening(true)
    }

    func shelfIconHitTarget() -> some View {
        self
            .font(PasteTheme.Typography.icon)
            .frame(width: PasteTheme.Typography.iconButtonSize, height: PasteTheme.Typography.iconButtonSize)
            .contentShape(Circle())
    }
}

/// Icon + title for shelf actions. Compact drops the title so English footers
/// can collapse to symbols instead of overflowing the 980pt panel.
struct ShelfActionLabel: View {
    let title: String
    let systemImage: String
    var compact: Bool = false

    var body: some View {
        HStack(spacing: PasteTheme.Typography.actionGap) {
            Image(systemName: systemImage)
                .font(PasteTheme.Typography.iconSmall)
                .symbolRenderingMode(.hierarchical)
            if !compact {
                Text(title)
                    .tracking(PasteTheme.Typography.chipTracking)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(compact ? 1 : PasteTheme.Typography.chipMinimumScale)
        .allowsTightening(true)
    }
}

/// Filled capsule used for the primary action on the shelf (启用 / 粘贴).
struct ShelfAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PasteTheme.Typography.button)
            .lineLimit(1)
            .minimumScaleFactor(PasteTheme.Typography.chipMinimumScale)
            .allowsTightening(true)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white)
            .padding(.horizontal, PasteTheme.Typography.buttonHorizontalPadding)
            .padding(.vertical, PasteTheme.Typography.buttonVerticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(PasteTheme.accent.opacity(configuration.isPressed ? 0.82 : 1))
            )
    }
}

/// Hairline capsule for secondary actions (复制 / 识别文字 / 下载).
struct ShelfQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PasteTheme.Typography.button)
            .lineLimit(1)
            .minimumScaleFactor(PasteTheme.Typography.chipMinimumScale)
            .allowsTightening(true)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(PasteTheme.ink.opacity(0.78))
            .padding(.horizontal, PasteTheme.Typography.buttonHorizontalPadding)
            .padding(.vertical, PasteTheme.Typography.buttonVerticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0.055))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

/// Rows of intrinsic-size children. Preview actions wrap instead of clipping titles to "…".
struct WrappingHStack: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        let rows = clustered(in: limit, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(CGFloat(0)) { $0 + $1.height }
            + CGFloat(max(rows.count - 1, 0)) * lineSpacing
        return CGSize(width: limit.isFinite ? limit : width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = clustered(in: bounds.width, subviews: subviews)
        var y = bounds.minY
        var index = 0
        for row in rows {
            var x = bounds.minX
            for size in row.sizes {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
                index += 1
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var sizes: [CGSize]
        var width: CGFloat
        var height: CGFloat
    }

    private func clustered(in limit: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        func flush() {
            guard !sizes.isEmpty else { return }
            rows.append(Row(sizes: sizes, width: width, height: height))
            sizes = []
            width = 0
            height = 0
        }

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !sizes.isEmpty, width + spacing + size.width > limit {
                flush()
            }
            if sizes.isEmpty {
                width = size.width
                height = size.height
            } else {
                width += spacing + size.width
                height = max(height, size.height)
            }
            sizes.append(size)
        }
        flush()
        return rows
    }
}
