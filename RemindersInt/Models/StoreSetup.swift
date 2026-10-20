import Foundation
import SwiftData

/// One-off store preparation run at launch, before notifications can be handled.
enum StoreSetup {
    @MainActor
    static func run(in context: ModelContext, defaults: UserDefaults = .standard) {
        migrateLegacyReminders(in: context)
        ExerciseLibrary.install(in: context)
        if !defaults.bool(forKey: AppStorageKey.hasSeededSpaces) {
            seedSpaces(in: context)
            defaults.set(true, forKey: AppStorageKey.hasSeededSpaces)
        }
        try? context.save()
    }

    /// V1 reminders become reminder tasks without a space. Same id, so already scheduled
    /// notifications and deep links keep pointing at them.
    static func migrateLegacyReminders(in context: ModelContext) {
        let legacy = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
        guard !legacy.isEmpty else { return }
        let existingIDs = Set(((try? context.fetch(FetchDescriptor<TaskItem>())) ?? []).map(\.id))
        for reminder in legacy {
            if !existingIDs.contains(reminder.id) {
                context.insert(TaskItem(
                    id: reminder.id,
                    title: reminder.title,
                    dueDate: reminder.dueDate,
                    repeatInterval: reminder.repeatInterval,
                    status: reminder.status,
                    createdAt: reminder.createdAt,
                    remindersSent: reminder.remindersSent,
                    rawTranscript: reminder.rawTranscript,
                    isReminder: true
                ))
            }
            context.delete(reminder)
        }
    }

    /// Root spaces and a few sub-spaces, on the first launch of V2.
    static func seedSpaces(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<Space>())) ?? 0
        guard existing == 0 else { return }

        let roots: [(name: String, color: String, symbol: String, children: [(String, String)])] = [
            ("Études", "#5E5CE6", "book.fill", [
                ("Finance", "chart.line.uptrend.xyaxis"),
                ("Maths", "function"),
                ("TAGE MAGE", "doc.text.fill"),
                ("Anglais", "text.bubble.fill"),
            ]),
            ("FieldZ", "#FF9F0A", "briefcase.fill", [
                ("Produit", "laptopcomputer"),
                ("Commercial", "person.2.fill"),
                ("Admin", "doc.text.fill"),
            ]),
            ("Mawiid", "#0A84FF", "calendar", []),
            ("Webentis", "#30B0C7", "globe", []),
            ("Sport", "#34C759", "figure.run", []),
            ("Perso", "#FF375F", "house.fill", []),
        ]
        for (index, root) in roots.enumerated() {
            let space = Space(name: root.name, colorHex: root.color, sfSymbol: root.symbol, sortOrder: index)
            context.insert(space)
            for (childIndex, child) in root.children.enumerated() {
                context.insert(Space(name: child.0, colorHex: root.color, sfSymbol: child.1, sortOrder: childIndex, parent: space))
            }
        }
    }
}
