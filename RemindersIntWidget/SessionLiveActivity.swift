import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Running session on the lock screen and in the Dynamic Island. Updated locally by the app.
struct SessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            SessionLockScreenView(state: context.state)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let color = Color(hexString: state.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SessionBadge(state: state, size: 44)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.spacePath.uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                        SessionTimer(startedAt: state.startedAt)
                            .font(.system(size: 28, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StopButton(size: 44)
                        .padding(.trailing, 4)
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            } compactTrailing: {
                SessionTimer(startedAt: state.startedAt)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: state.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
            }
            .keylineTint(color)
            .widgetURL(URL(string: "remindersint://tracking"))
        }
    }
}

/// Same layout as the reminder notification card: badge, "ÉTUDES · TAGE MAGE", chrono, Stop.
/// The background is the system lock screen material.
private struct SessionLockScreenView: View {
    let state: SessionActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            SessionBadge(state: state, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.spacePath.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.75))
                    .lineLimit(1)
                SessionTimer(startedAt: state.startedAt)
                    .font(.system(size: 30, weight: .bold))
            }
            Spacer(minLength: 8)
            StopButton(size: 52)
        }
        .padding(16)
        .widgetURL(URL(string: "remindersint://tracking"))
    }
}

private struct SessionBadge: View {
    let state: SessionActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        Image(systemName: state.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hexString: state.colorHex), in: .rect(cornerRadius: size * 0.325))
    }
}

private struct SessionTimer: View {
    let startedAt: Date

    var body: some View {
        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
            .monospacedDigit()
            .multilineTextAlignment(.leading)
    }
}

/// Red translucent Stop, runs StopSessionIntent in the app's process.
private struct StopButton: View {
    let size: CGFloat

    var body: some View {
        Button(intent: StopSessionIntent()) {
            RoundedRectangle(cornerRadius: 4)
                .fill(.white)
                .frame(width: size * 0.34, height: size * 0.34)
                .frame(width: size, height: size)
                .background(Color(red: 1, green: 0.27, blue: 0.23).opacity(0.85), in: .rect(cornerRadius: size * 0.35))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Arrêter la session")
    }
}

private extension Color {
    /// "#5E5CE6"; grey when unreadable. (The app's palette is not part of the extension.)
    init(hexString: String) {
        let digits = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
