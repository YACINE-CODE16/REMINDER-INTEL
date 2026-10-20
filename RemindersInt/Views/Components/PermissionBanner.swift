import SwiftUI
import UIKit

/// Discreet banner for a refused permission, with a link to the app's settings.
struct PermissionBanner: View {
    let message: String
    var systemImage = "bell.slash.fill"
    var actionTitle = "Activer"
    let settingsURL: String
    /// Light text on the dark dictation panel.
    var onDark = false

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.red)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(onDark ? .white.opacity(0.85) : Palette.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(actionTitle) {
                if let url = URL(string: settingsURL) { openURL(url) }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(onDark ? .white : Palette.blue)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background((onDark ? Color.white.opacity(0.1) : Palette.red.opacity(0.08)), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
