import AppIntents
import SwiftUI
import WidgetKit

struct NextPrayerEntry: TimelineEntry {
    let date: Date
    let next: PrayerSnapshot.Slot?
    /// Called and not ticked yet.
    let current: PrayerSnapshot.Slot?
    let isModuleOn: Bool
}

struct NextPrayerProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextPrayerEntry {
        let time = Date.now.addingTimeInterval(5040)
        let slot = PrayerSnapshot.Slot(id: "placeholder", prayer: "asr", name: "Asr", time: time, deadline: time, end: time, isDone: false)
        return NextPrayerEntry(date: .now, next: slot, current: nil, isModuleOn: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextPrayerEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.entries(from: .now)[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextPrayerEntry>) -> Void) {
        completion(Timeline(entries: Self.entries(from: .now), policy: .atEnd))
    }

    /// One entry now, then one at each prayer time and at each end of a prayer's window.
    private static func entries(from now: Date) -> [NextPrayerEntry] {
        guard let snapshot = PrayerSnapshot.load() else {
            return [NextPrayerEntry(date: now, next: nil, current: nil, isModuleOn: false)]
        }
        let moments = Set(snapshot.slots.flatMap { [$0.time, $0.end] }.filter { $0 > now })
        return ([now] + moments.sorted()).map { date in
            NextPrayerEntry(date: date, next: snapshot.next(after: date), current: snapshot.current(at: date), isModuleOn: true)
        }
    }
}

struct NextPrayerView: View {
    let entry: NextPrayerEntry

    private static let locale = Locale(identifier: "fr_FR")

    var body: some View {
        Group {
            if let next = entry.next {
                VStack(alignment: .leading, spacing: 0) {
                    Label("\(next.name) · \(next.time.formatted(.dateTime.hour().minute().locale(Self.locale)))", systemImage: "moon.stars.fill")
                        .font(.headline)
                        .widgetAccentable()
                    Text(timerInterval: entry.date...max(entry.date, next.time), countsDown: true)
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                    Text(entry.current.map { "\($0.name) à faire" } ?? "Prochaine prière")
                        .font(.caption)
                        .lineLimit(1)
                }
            } else {
                Label(entry.isModuleOn ? "Horaires à venir" : "Module Prière inactif", systemImage: "moon.stars")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "remindersint://prayer"))
        .containerBackground(for: .widget) { Color.clear }
    }
}

/// Lock Screen widget: next prayer with a live countdown.
struct NextPrayerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nextPrayer, provider: NextPrayerProvider()) { entry in
            NextPrayerView(entry: entry)
        }
        .configurationDisplayName("Prochaine prière")
        .description("Prochaine prière et compte à rebours.")
        .supportedFamilies([.accessoryRectangular])
    }
}

/// Control Center / lock screen control that ticks the prayer currently due.
struct CheckPrayerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.checkPrayer) {
            ControlWidgetButton(action: CheckPrayerIntent()) {
                Label("Prière faite", systemImage: "checkmark.seal.fill")
            }
        }
        .displayName("Prière faite")
        .description("Coche la prière en cours.")
    }
}
