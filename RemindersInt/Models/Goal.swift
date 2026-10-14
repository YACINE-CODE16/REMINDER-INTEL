import Foundation
import SwiftData

nonisolated enum GoalKind: String, Codable, CaseIterable, Identifiable {
    /// Tracked time of the space and its descendants over the period, automatic.
    case hours
    /// Manual counter (+1 on the card or by voice).
    case count
    /// Result to reach, with sub-steps and an achieved state ticked by the user.
    case outcome

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hours: "Heures"
        case .count: "Compteur"
        case .outcome: "Résultat"
        }
    }
}

nonisolated enum GoalPeriod: String, Codable, CaseIterable, Identifiable {
    case week
    case month
    case untilDate
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: "Par semaine"
        case .month: "Par mois"
        case .untilDate: "Jusqu'à une date"
        case .none: "Sans période"
        }
    }

    /// "sem.", "mois", nil.
    var shortLabel: String? {
        switch self {
        case .week: "sem."
        case .month: "mois"
        case .untilDate, .none: nil
        }
    }
}

@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    /// Always set by the app (optional for the cascade delete from Space).
    var space: Space?
    var title: String
    var kind: GoalKind
    var target: Double
    /// "h", "séances", "clubs".
    var unit: String?
    var period: GoalPeriod
    var deadline: Date?
    /// Counter of count goals (reset at each new week / month) and unused otherwise.
    var currentManual: Double
    /// Start of the period `currentManual` belongs to, for weekly and monthly counters.
    var counterPeriodStart: Date?
    /// Ticked by the user for outcome goals.
    var isAchieved: Bool
    var achievedAt: Date?
    var createdAt: Date
    var isArchived: Bool
    @Relationship(deleteRule: .cascade, inverse: \GoalStep.goal) var steps: [GoalStep] = []

    init(
        id: UUID = UUID(),
        space: Space,
        title: String,
        kind: GoalKind,
        target: Double,
        unit: String? = nil,
        period: GoalPeriod = .none,
        deadline: Date? = nil,
        currentManual: Double = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.space = space
        self.title = title
        self.kind = kind
        self.target = target
        self.unit = unit
        self.period = period
        self.deadline = deadline
        self.currentManual = currentManual
        self.counterPeriodStart = nil
        self.isAchieved = false
        self.achievedAt = nil
        self.createdAt = createdAt
        self.isArchived = false
    }

    var sortedSteps: [GoalStep] { steps.sorted { $0.sortOrder < $1.sortOrder } }
}

@Model
final class GoalStep {
    @Attribute(.unique) var id: UUID
    var title: String
    var isDone: Bool
    var sortOrder: Int
    var goal: Goal?

    init(id: UUID = UUID(), title: String, isDone: Bool = false, sortOrder: Int) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.sortOrder = sortOrder
    }
}

/// Progress of a goal, computed from the sessions (hours) or the stored counter (count).
enum GoalMath {
    /// Window the goal is measured on: this calendar week / month, creation → deadline,
    /// or creation → now.
    static func window(for goal: Goal, now: Date, calendar: Calendar = .app) -> DateInterval {
        switch goal.period {
        case .week:
            return TimeTotals.week(containing: now, calendar: calendar)
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
        case .untilDate:
            let end = max(goal.deadline ?? now, goal.createdAt)
            return DateInterval(start: min(goal.createdAt, end), end: end)
        case .none:
            return DateInterval(start: min(goal.createdAt, now), end: max(goal.createdAt, now))
        }
    }

    /// Hours over the window from sessions in the goal's space subtree.
    static func hours(_ goal: Goal, sessions: [Session], now: Date) -> Double {
        guard let space = goal.space else { return 0 }
        let window = window(for: goal, now: now)
        return TimeTotals.seconds(sessions, in: window, within: space, now: now) / 3600
    }

    /// Counter value for the current period: a weekly or monthly counter left from a
    /// previous period reads 0.
    static func count(_ goal: Goal, now: Date) -> Double {
        switch goal.period {
        case .week, .month:
            guard let start = goal.counterPeriodStart, window(for: goal, now: now).contains(start) else { return 0 }
            return goal.currentManual
        case .untilDate, .none:
            return goal.currentManual
        }
    }

    /// Current value: hours, counter, or done steps for an outcome.
    static func value(_ goal: Goal, sessions: [Session], now: Date) -> Double {
        switch goal.kind {
        case .hours: hours(goal, sessions: sessions, now: now)
        case .count: count(goal, now: now)
        case .outcome: Double(goal.steps.filter(\.isDone).count)
        }
    }

    /// 0…1 progress; outcome goals use their steps (achieved = 1).
    static func fraction(_ goal: Goal, sessions: [Session], now: Date) -> Double {
        switch goal.kind {
        case .hours, .count:
            guard goal.target > 0 else { return 0 }
            return min(1, value(goal, sessions: sessions, now: now) / goal.target)
        case .outcome:
            if goal.isAchieved { return 1 }
            guard !goal.steps.isEmpty else { return 0 }
            return Double(goal.steps.filter(\.isDone).count) / Double(goal.steps.count)
        }
    }

    static func isAchieved(_ goal: Goal, sessions: [Session], now: Date) -> Bool {
        switch goal.kind {
        case .hours, .count: goal.target > 0 && value(goal, sessions: sessions, now: now) >= goal.target
        case .outcome: goal.isAchieved
        }
    }

    /// Share of the period already elapsed, the expected progress on a steady pace.
    static func expectedFraction(_ goal: Goal, now: Date) -> Double {
        let window = window(for: goal, now: now)
        guard window.duration > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(window.start) / window.duration))
    }

    /// Sort key, most urgent first: pending deadlines by date, then the goals most behind
    /// their period's pace, achieved goals last.
    static func urgency(_ goal: Goal, sessions: [Session], now: Date) -> (Int, Double) {
        if isAchieved(goal, sessions: sessions, now: now) { return (2, 0) }
        if let deadline = goal.deadline, goal.kind == .outcome || goal.period == .untilDate {
            return (0, deadline.timeIntervalSince(now))
        }
        let lag = expectedFraction(goal, now: now) - fraction(goal, sessions: sessions, now: now)
        return (1, -lag)
    }

    static func sortedByUrgency(_ goals: [Goal], sessions: [Session], now: Date) -> [Goal] {
        goals.sorted { lhs, rhs in
            let left = urgency(lhs, sessions: sessions, now: now)
            let right = urgency(rhs, sessions: sessions, now: now)
            return left.0 != right.0 ? left.0 < right.0 : left.1 < right.1
        }
    }

    /// "12h / 20h", "3/10", "4 / 10 clubs"; for an outcome, its deadline.
    static func valueLabel(_ goal: Goal, sessions: [Session], now: Date) -> String {
        switch goal.kind {
        case .hours:
            let value = TimeFormat.short(hours(goal, sessions: sessions, now: now) * 3600)
            return "\(value) / \(number(goal.target))h"
        case .count:
            let value = number(count(goal, now: now))
            guard let unit = goal.unit, !unit.isEmpty else { return "\(value)/\(number(goal.target))" }
            return "\(value) / \(number(goal.target)) \(unit)"
        case .outcome:
            if goal.isAchieved { return "Atteint" }
            return goal.deadline.map(deadlineLabel) ?? "Sans échéance"
        }
    }

    /// "dans 5 j", "demain", "aujourd'hui", "en retard".
    static func deadlineLabel(_ deadline: Date) -> String {
        let calendar = Calendar.app
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: calendar.startOfDay(for: deadline)).day ?? 0
        let date = deadline.formatted(.dateTime.day().month(.abbreviated).locale(.app))
        switch days {
        case ..<0: return "\(date) · en retard"
        case 0: return "aujourd'hui"
        case 1: return "demain"
        case 2...14: return "\(date) · dans \(days) j"
        default: return date
        }
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// +1 on a counter, starting a new period if needed.
    static func increment(_ goal: Goal, by amount: Double = 1, now: Date = .now) {
        if goal.period == .week || goal.period == .month {
            let window = window(for: goal, now: now)
            if goal.counterPeriodStart.map({ !window.contains($0) }) ?? true {
                goal.currentManual = 0
                goal.counterPeriodStart = window.start
            }
        }
        goal.currentManual = max(0, goal.currentManual + amount)
    }
}
