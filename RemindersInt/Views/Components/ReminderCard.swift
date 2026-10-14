import SwiftUI

struct ReminderCard: View {
    let reminder: Reminder

    private var isCancelled: Bool { reminder.status == .cancelled }

    private var subtitle: String {
        switch reminder.status {
        case .done: return "Fait"
        case .cancelled: return "Annulé"
        case .pending:
            if reminder.repeatInterval == .none { return "Sans relance" }
            return "Relance \(reminder.repeatInterval.label.lowercased())"
        }
    }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Text(reminder.dueDate.formatted(.dateTime.hour().minute().locale(.app)))
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isCancelled ? Palette.secondary : Palette.text)
                    .frame(width: 50, alignment: .leading)

                Rectangle()
                    .fill(Palette.secondary.opacity(0.25))
                    .frame(width: 1, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title)
                        .font(.system(size: 16, weight: .semibold))
                        .strikethrough(isCancelled)
                        .foregroundStyle(isCancelled ? Palette.secondary : Palette.text)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }

                Spacer(minLength: 8)

                statusBadge
            }
        }
        .opacity(isCancelled ? 0.6 : 1)
        .contentShape(.rect(cornerRadius: 24))
    }

    private var statusBadge: some View {
        let style: (symbol: String, foreground: Color, background: Color, label: String) = switch reminder.status {
        case .pending: ("arrow.clockwise", Palette.secondary, Palette.text.opacity(0.06), "En attente")
        case .done: ("checkmark", .white, Palette.green, "Fait")
        case .cancelled: ("xmark", Palette.secondary, Palette.text.opacity(0.06), "Annulé")
        }
        return Image(systemName: style.symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(style.foreground)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 34, height: 34)
            .background(style.background, in: .rect(cornerRadius: 12))
            .accessibilityLabel(style.label)
    }
}
