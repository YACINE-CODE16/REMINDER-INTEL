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

    /// The task's space (or an ancestor) has an outcome goal due within 7 days.
    private var hasUpcomingOutcome: Bool {
        let now = Date.now
        let limit = now.addingTimeInterval(7 * 86_400)
        var current = item.space
        while let space = current {
            if space.goals.contains(where: { goal in
                goal.kind == .outcome && !goal.isArchived && !goal.isAchieved
                    && (goal.deadline.map { $0 >= Calendar.app.startOfDay(for: now) && $0 <= limit } ?? false)
            }) { return true }
            current = space.parent
        }
        return false
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
                    HStack(spacing: 6) {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(1)
                        if hasUpcomingOutcome {
                            Text("Objectif")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(item.space?.color ?? Palette.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((item.space?.color ?? Palette.secondary).opacity(0.14), in: .capsule)
                                .fixedSize()
                        }
                    }
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
