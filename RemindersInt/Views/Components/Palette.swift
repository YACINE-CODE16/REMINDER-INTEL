import SwiftUI

enum Palette {
    static let background = Color(hex: 0xF2F2F7)
    static let text = Color(hex: 0x1C1C1E)
    static let secondary = Color(hex: 0x6E6E73)
    static let green = Color(hex: 0x34C759)
    static let red = Color(hex: 0xFF453A)
    static let lavender = Color(hex: 0xB9BEFF)
    static let blush = Color(hex: 0xFFC9DC)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Animation {
    /// Shared spring for day, status and presentation changes.
    static let appSpring = Animation.spring(duration: 0.35, bounce: 0.2)
}

/// Light iOS grey with soft radial halos that give the glass something to refract.
/// Stays fixed behind scrolling content.
struct AppBackground: View {
    var body: some View {
        ZStack {
            Palette.background
            RadialGradient(
                colors: [Palette.lavender.opacity(0.55), Palette.lavender.opacity(0)],
                center: UnitPoint(x: 0.05, y: 0.02),
                startRadius: 0,
                endRadius: 420
            )
            RadialGradient(
                colors: [Palette.blush.opacity(0.5), Palette.blush.opacity(0)],
                center: UnitPoint(x: 0.98, y: 0.08),
                startRadius: 0,
                endRadius: 360
            )
            RadialGradient(
                colors: [Palette.lavender.opacity(0.22), Palette.lavender.opacity(0)],
                center: UnitPoint(x: 0.85, y: 0.9),
                startRadius: 0,
                endRadius: 380
            )
        }
        .ignoresSafeArea()
    }
}
