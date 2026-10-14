import SwiftUI

/// Dated task in the day and month lists. The bar between time and title takes the colour
/// of the task's space; tasks without a space stay neutral.
struct TaskCard: View {
    let item: TaskItem

    private var isCancelled: Bool { item.status == .cancelled }

    private var subtitle: String {
        let state: String = switch item.status {
        case .done: "Fait"
        case .cancelled: "Annulé"
        case .pending where !item.isReminder: "À faire"
        case .pending where item.repeatInterval == .none: "Sans relance"
        case .pending: "Relance \(item.repeatInterval.label.lowercased())"
        }
        guard let space = item.space else { return state }
        return "\(space.displayPath) · \(state)"
    }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Text(item.dueDate?.formatted(.dateTime.hour().minute().locale(.app)) ?? "—")
                    .font(.system(size: 17, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isCancelled ? Palette.secondary : Palette.text)
                    .frame(width: 50, alignment: .leading)

                Capsule()
                    .fill(item.space?.color ?? Palette.secondary.opacity(0.25))
                    .frame(width: item.space == nil ? 1 : 3, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .strikethrough(isCancelled)
                        .foregroundStyle(isCancelled ? Palette.secondary : Palette.text)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                statusBadge
            }
        }
        .opacity(isCancelled ? 0.6 : 1)
        .contentShape(.rect(cornerRadius: 24))
    }

    private var statusBadge: some View {
        let style: (symbol: String, foreground: Color, background: Color, label: String) = switch item.status {
        case .pending where item.isReminder: ("arrow.clockwise", Palette.secondary, Palette.text.opacity(0.06), "Rappel en attente")
        case .pending: ("circle", Palette.secondary, Palette.text.opacity(0.06), "À faire")
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
