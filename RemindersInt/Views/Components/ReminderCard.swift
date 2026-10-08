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
        GlassCard {
            HStack(spacing: 14) {
                Text(reminder.dueDate.formatted(.dateTime.hour().minute().locale(.app)))
                    .font(.headline.bold())
                    .monospacedDigit()
                    .foregroundStyle(isCancelled ? Palette.secondary : Palette.text)
                    .frame(width: 54, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title)
                        .font(.body.weight(.medium))
                        .strikethrough(isCancelled)
                        .foregroundStyle(isCancelled ? Palette.secondary : Palette.text)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }

                Spacer(minLength: 8)

                statusIcon
                    .font(.title3.weight(.semibold))
            }
        }
        .opacity(isCancelled ? 0.6 : 1)
        .contentShape(.rect(cornerRadius: 24))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch reminder.status {
        case .pending:
            Image(systemName: "arrow.clockwise")
                .foregroundStyle(Palette.secondary)
                .accessibilityLabel("En attente")
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.green)
                .accessibilityLabel("Fait")
        case .cancelled:
            Image(systemName: "xmark.circle")
                .foregroundStyle(Palette.secondary)
                .accessibilityLabel("Annulé")
        }
    }
}
