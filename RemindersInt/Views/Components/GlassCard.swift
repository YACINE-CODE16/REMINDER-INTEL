import SwiftUI

/// White translucent Liquid Glass card used across the app.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.white.opacity(0.55)), in: .rect(cornerRadius: cornerRadius))
            .glassRim(.rect(cornerRadius: cornerRadius))
            .softShadow()
    }
}

extension View {
    /// 1 pt white edge drawn on top of a glass surface.
    func glassRim<S: InsettableShape>(_ shape: S, opacity: Double = 0.9) -> some View {
        overlay {
            shape
                .strokeBorder(.white.opacity(opacity), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    /// Very light drop shadow for cards.
    func softShadow() -> some View {
        shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}
