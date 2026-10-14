#if DEBUG
import Foundation
import SwiftData

/// Three goals of each kind (`-seedDemoGoals YES`, inserted once).
enum DemoGoals {
    static func insert(into context: ModelContext, now: Date = .now) {
        let existing = (try? context.fetchCount(FetchDescriptor<Goal>())) ?? 0
        guard existing == 0 else { return }
        let calendar = Calendar.app
        let spaces = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        func space(_ name: String) -> Space? { spaces.first { $0.name == name } }
        func inDays(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
        }
        let created = inDays(-20)

        guard let studies = space("Études"), let product = space("Produit"), let english = space("Anglais"),
              let sales = space("Commercial"), let sport = space("Sport"), let tage = space("TAGE MAGE"),
              let finance = space("Finance"), let mawiid = space("Mawiid")
        else { return }

        // Hours, from the sessions.
        context.insert(Goal(space: studies, title: "20h d'études", kind: .hours, target: 20, unit: "h", period: .week, createdAt: created))
        context.insert(Goal(space: product, title: "8h sur le produit", kind: .hours, target: 8, unit: "h", period: .week, createdAt: created))
        context.insert(Goal(space: english, title: "Anglais ce mois", kind: .hours, target: 15, unit: "h", period: .month, createdAt: created))

        // Counters.
        let clubs = Goal(space: sales, title: "Clubs signés", kind: .count, target: 10, unit: "clubs", period: .none, currentManual: 3, createdAt: created)
        let sessions = Goal(space: sport, title: "Séances de sport", kind: .count, target: 3, unit: "séances", period: .week, currentManual: 1, createdAt: created)
        sessions.counterPeriodStart = TimeTotals.week(containing: now).start
        let tests = Goal(space: tage, title: "Tests blancs", kind: .count, target: 4, unit: "tests", period: .untilDate, deadline: inDays(30), currentManual: 1, createdAt: created)
        [clubs, sessions, tests].forEach(context.insert)

        // Outcomes with steps.
        let outcomes: [(Space, String, Int, [(String, Bool)])] = [
            (finance, "Valider le partiel de finance", 5, [("Fiches chapitres 1 à 4", true), ("Annales 2024", false), ("Révision finale", false)]),
            (mawiid, "Lancer la V2 de Mawiid", 20, [("Maquettes validées", true), ("Bêta testeurs", true), ("Publication", false)]),
            (english, "750 au TOEIC", 40, [("Test blanc", false), ("Inscription", false)]),
        ]
        for (space, title, days, steps) in outcomes {
            let goal = Goal(space: space, title: title, kind: .outcome, target: 1, period: .untilDate, deadline: inDays(days), createdAt: created)
            context.insert(goal)
            for (index, step) in steps.enumerated() {
                let item = GoalStep(title: step.0, isDone: step.1, sortOrder: index)
                item.goal = goal
                context.insert(item)
            }
        }
        try? context.save()
    }
}
#endif
