#if DEBUG
import Foundation
import SwiftData

/// Two weeks of sessions for checking the stats (`-seedDemoSessions YES`, inserted once).
enum DemoSessions {
    static func insert(into context: ModelContext, now: Date = .now) {
        let existing = (try? context.fetchCount(FetchDescriptor<Session>())) ?? 0
        guard existing == 0 else { return }
        let calendar = Calendar.app
        let spaces = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        func space(_ name: String) -> Space? { spaces.first { $0.name == name } }

        // (space, start hour, start minute, minutes, which days: offset → included)
        let pattern: [(String, Int, Int, Int, (Int) -> Bool)] = [
            ("Maths", 8, 30, 90, { _ in true }),                       // every day: Études streak
            ("Finance", 14, 0, 75, { $0 % 2 == 0 }),
            ("TAGE MAGE", 17, 0, 60, { $0 % 3 == 1 }),
            ("Anglais", 21, 0, 30, { $0 % 4 == 0 }),
            ("Produit", 10, 15, 120, { $0 % 7 != 5 && $0 % 7 != 6 }),
            ("Commercial", 16, 0, 45, { $0 % 7 == 2 || $0 % 7 == 4 }),
            ("Sport", 19, 0, 60, { $0 % 2 == 1 }),
            ("Mawiid", 11, 0, 50, { $0 % 5 == 3 }),
            ("Perso", 20, 0, 40, { $0 % 7 == 6 }),
        ]
        let notes = ["Chapitre 4", "Exercices", "Relecture", nil, "Cas pratique", nil]
        for daysAgo in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) else { continue }
            for (index, entry) in pattern.enumerated() where entry.4(daysAgo) {
                guard let space = space(entry.0),
                      let start = calendar.date(bySettingHour: entry.1, minute: entry.2, second: 0, of: day)
                else { continue }
                let end = start.addingTimeInterval(TimeInterval(entry.3 * 60))
                // Today: only what is already over.
                guard end <= now else { continue }
                context.insert(Session(space: space, startedAt: start, endedAt: end, note: notes[(index + daysAgo) % notes.count]))
            }
        }
        try? context.save()
    }
}
#endif
