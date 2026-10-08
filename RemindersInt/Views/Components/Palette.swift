import SwiftUI

enum Palette {
    static let background = Color(hex: 0xF2F2F7)
    static let text = Color(hex: 0x1C1C1E)
    static let secondary = Color(hex: 0x6E6E73)
    static let green = Color(hex: 0x34C759)
    static let red = Color(hex: 0xFF453A)
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

/// Light iOS grey with a faint green tint at the top.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Palette.green.opacity(0.07), Palette.background],
            startPoint: .top,
            endPoint: .center
        )
        .background(Palette.background)
        .ignoresSafeArea()
    }
}
