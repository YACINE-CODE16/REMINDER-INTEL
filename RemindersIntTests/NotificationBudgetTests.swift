import Foundation
import Testing
@testable import RemindersInt

/// Selection under iOS's 64 pending notifications.
struct NotificationBudgetTests {
    typealias Candidate = NotificationBudget.Candidate

    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func candidate(_ id: String, minutes: Double, _ priority: NotificationBudget.Priority) -> Candidate {
        Candidate(id: id, fireDate: Self.now.addingTimeInterval(minutes * 60), priority: priority)
    }

    /// Over the limit: prayers first, then reminders by date, then follow-ups, then "Rien tracké".
    @Test func keepsHighestPrioritiesThenSoonest() {
        var candidates: [Candidate] = []
        candidates += (0..<7).map { candidate("daily-tracking-\($0)", minutes: Double($0) * 1440 + 60, .dailyTracking) }
        candidates += (0..<40).map { candidate("followup-\($0)", minutes: Double($0) * 5, .followUp) }
        candidates += (0..<20).map { candidate("reminder-\($0)", minutes: Double(100 - $0), .reminder) }
        candidates += (0..<10).map { candidate("prayer-\($0)", minutes: Double($0) * 300, .prayerAndLive) }

        let kept = NotificationBudget.select(candidates, limit: 64)
        #expect(kept.count == 64)
        #expect(kept.prefix(10).allSatisfy { $0.priority == .prayerAndLive })
        // All 20 reminders, soonest due date first.
        let reminders = kept.filter { $0.priority == .reminder }
        #expect(reminders.count == 20)
        #expect(reminders.map(\.fireDate) == reminders.map(\.fireDate).sorted())
        // 34 follow-ups fit, the soonest ones; no "Rien tracké" left.
        let followUps = kept.filter { $0.priority == .followUp }
        #expect(followUps.count == 34)
        #expect(followUps.last?.id == "followup-33")
        #expect(!kept.contains { $0.priority == .dailyTracking })
    }

    @Test func underTheLimitEverythingStays() {
        let candidates = (0..<10).map { candidate("x-\($0)", minutes: Double($0), .followUp) }
        #expect(NotificationBudget.select(candidates).count == 10)
    }

    /// Priorities read from the identifiers of each service.
    @Test func prioritiesFromIdentifiers() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        let now = Self.now
        let today = now.addingTimeInterval(3600)
        let tomorrow = now.addingTimeInterval(26 * 3600)
        let id = UUID().uuidString
        func priority(_ identifier: String, _ date: Date) -> NotificationBudget.Priority {
            NotificationBudget.priority(of: identifier, fireDate: date, now: now, calendar: calendar)
        }
        #expect(priority("prayer-20260922-asr-0", tomorrow) == .prayerAndLive)
        #expect(priority("prayer-20260921-asr-2", today) == .prayerAndLive)
        #expect(priority("prayer-20260922-asr-2", tomorrow) == .followUp)
        #expect(priority("\(id)-0", today) == .reminder)
        #expect(priority("\(id)-3", today) == .followUp)
        #expect(priority("daily-tracking-2", tomorrow) == .dailyTracking)
        #expect(priority("session-long", today) == .prayerAndLive)
        #expect(priority("gym-rest", today) == .prayerAndLive)
    }
}
