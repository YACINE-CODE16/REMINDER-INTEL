import SwiftUI
import WidgetKit

struct NextReminderEntry: TimelineEntry {
    let date: Date
    let reminder: WidgetSnapshot.Item?
}

struct NextReminderProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextReminderEntry {
        NextReminderEntry(date: .now, reminder: WidgetSnapshot.Item(id: UUID(), title: "Appeler Karim", dueDate: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (NextReminderEntry) -> Void) {
        completion(Self.entries(from: .now).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextReminderEntry>) -> Void) {
        completion(Timeline(entries: Self.entries(from: .now), policy: .atEnd))
    }

    /// One entry now, then one each time the next reminder's time passes.
    private static func entries(from now: Date) -> [NextReminderEntry] {
        let upcoming = (WidgetSnapshot.load()?.upcoming ?? [])
            .filter { $0.dueDate > now }
            .sorted { $0.dueDate < $1.dueDate }
        var entries = [NextReminderEntry(date: now, reminder: upcoming.first)]
        for (index, item) in upcoming.enumerated() {
            let next = upcoming.indices.contains(index + 1) ? upcoming[index + 1] : nil
            entries.append(NextReminderEntry(date: item.dueDate, reminder: next))
        }
        return entries
    }
}

struct NextReminderView: View {
    let entry: NextReminderEntry

    private static let locale = Locale(identifier: "fr_FR")

    var body: some View {
        Group {
            if let reminder = entry.reminder {
                VStack(alignment: .leading, spacing: 2) {
                    Label(timeLabel(for: reminder.dueDate), systemImage: "bell.fill")
                        .font(.headline)
                        .widgetAccentable()
                    Text(reminder.title)
                        .font(.body)
                        .lineLimit(2)
                }
                .widgetURL(URL(string: "remindersint://reminder/\(reminder.id.uuidString)"))
            } else {
                Label("Aucun rappel à venir", systemImage: "checkmark.circle")
                    .font(.headline)
                    .widgetURL(URL(string: "remindersint://capture"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    /// "16:00" today, "jeu. 16:00" on another day.
    private func timeLabel(for date: Date) -> String {
        let time = date.formatted(.dateTime.hour().minute().locale(Self.locale))
        guard !Calendar.current.isDateInToday(date) else { return time }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).locale(Self.locale))) \(time)"
    }
}

/// Lock Screen widget showing the next pending reminder.
struct NextReminderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nextReminder, provider: NextReminderProvider()) { entry in
            NextReminderView(entry: entry)
        }
        .configurationDisplayName("Prochain rappel")
        .description("Heure et titre du prochain rappel en attente.")
        .supportedFamilies([.accessoryRectangular])
    }
}
