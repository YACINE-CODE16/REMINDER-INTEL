import Foundation
import SwiftData

/// Sample reminders and tasks inserted on first launch so the views are not empty.
enum DemoData {
    static func insert(into context: ModelContext, now: Date = .now) {
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: now)

        func date(dayOffset: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let spaces = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        func space(_ name: String) -> Space? { spaces.first { $0.name == name } }

        let samples: [TaskItem] = [
            TaskItem(title: "Appeler Karim", dueDate: date(dayOffset: 0, hour: 9, minute: 30), repeatInterval: .every15min, status: .done),
            TaskItem(title: "Acheter du pain", dueDate: date(dayOffset: 0, hour: 18), repeatInterval: .every30min, space: space("Perso")),
            TaskItem(title: "Envoyer la facture", dueDate: date(dayOffset: 1, hour: 10), repeatInterval: .hourly, space: space("Admin")),
            TaskItem(title: "Prendre rendez-vous chez le dentiste", dueDate: date(dayOffset: 7, hour: 14), repeatInterval: .every15min),
            TaskItem(title: "Payer le loyer", dueDate: date(dayOffset: 9, hour: 9), repeatInterval: .none, space: space("Perso")),
            TaskItem(title: "Rendre le cas de corporate finance", dueDate: date(dayOffset: -1, hour: 18), isReminder: false, space: space("Finance")),
            TaskItem(title: "Exercices de probabilités", dueDate: date(dayOffset: 2, hour: 9), isReminder: false, space: space("Maths")),
            TaskItem(title: "Test blanc TAGE MAGE", dueDate: date(dayOffset: 4, hour: 9), isReminder: false, space: space("TAGE MAGE")),
            TaskItem(title: "Fiche de vocabulaire", dueDate: nil, isReminder: false, space: space("Anglais")),
            TaskItem(title: "Relancer le client Dupont", dueDate: date(dayOffset: -2, hour: 10), isReminder: false, space: space("Commercial")),
            TaskItem(title: "Séance jambes", dueDate: date(dayOffset: 1, hour: 19), isReminder: false, space: space("Sport")),
            TaskItem(title: "Lire le chapitre 3", dueDate: date(dayOffset: -3, hour: 9), status: .done, isReminder: false, space: space("Études")),
        ]
        samples.forEach(context.insert)
    }
}
