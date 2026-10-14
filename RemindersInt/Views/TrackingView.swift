import SwiftUI

/// Suivi tab. Time tracking arrives in step 6b; placeholder until then.
struct TrackingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TEMPS ET SÉANCES")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                Text("Suivi")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.text)
            }
            GlassCard {
                Label("Le suivi du temps par espace arrive bientôt.", systemImage: "timer")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
}
