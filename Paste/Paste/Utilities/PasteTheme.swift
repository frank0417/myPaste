import SwiftUI
import AppKit

enum PasteTheme {
    static let accent = Color(hex: "#0F766E") ?? .teal
    static let ink = Color(hex: "#1B2A2F") ?? .primary
    static let mist = Color(hex: "#E8F1F0") ?? .gray.opacity(0.2)
    static let sand = Color(hex: "#F3EFE7") ?? .gray.opacity(0.15)
    static let coral = Color(hex: "#E07A5F") ?? .orange

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
