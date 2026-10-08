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
            .glassEffect(.regular.tint(.white.opacity(0.6)), in: .rect(cornerRadius: cornerRadius))
    }
}
