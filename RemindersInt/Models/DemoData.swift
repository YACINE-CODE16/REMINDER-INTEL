import Foundation
import SwiftData

/// Sample reminders inserted on first launch so the views are not empty.
enum DemoData {
    static func insert(into context: ModelContext, now: Date = .now) {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: now)

        func date(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let samples: [Reminder] = [
            Reminder(title: "Appeler Karim", dueDate: date(dayOffset: 0, hour: 9, minute: 30), repeatInterval: .every15min, status: .done),
            Reminder(title: "Acheter du pain", dueDate: date(dayOffset: 0, hour: 18), repeatInterval: .every30min),
            Reminder(title: "Envoyer la facture", dueDate: date(dayOffset: 1, hour: 10), repeatInterval: .hourly),
            Reminder(title: "Prendre rendez-vous chez le dentiste", dueDate: date(dayOffset: 7, hour: 14), repeatInterval: .every15min),
            Reminder(title: "Payer le loyer", dueDate: date(dayOffset: 9, hour: 9), repeatInterval: .none),
        ]
        samples.forEach(context.insert)
    }
}
