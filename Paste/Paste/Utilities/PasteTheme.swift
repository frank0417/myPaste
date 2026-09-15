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
}
