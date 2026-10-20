import Foundation
import SwiftData

/// Time spent in a space. At most one session is open (endedAt == nil) at a time.
/// Closed sessions never cross midnight: they are split when closed or logged.
@Model
final class Session {
    @Attribute(.unique) var id: UUID
    /// Always set by the app. Optional only because SwiftData to-one relationships must be
    /// optional for the cascade delete from Space to be safe.
    var space: Space?
    var startedAt: Date
    var endedAt: Date?
    var note: String?
    /// What was dictated, kept for debugging the parser.
    var rawTranscript: String?
    /// Set when the session is a gym workout.
    @Relationship(deleteRule: .cascade, inverse: \Workout.session) var workout: Workout?

    init(
        id: UUID = UUID(),
        space: Space,
        startedAt: Date,
        endedAt: Date? = nil,
        note: String? = nil,
        rawTranscript: String? = nil
    ) {
        self.id = id
        self.space = space
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.note = note
        self.rawTranscript = rawTranscript
    }

    var isActive: Bool { endedAt == nil }

    func duration(now: Date = .now) -> TimeInterval {
        max(0, (endedAt ?? now).timeIntervalSince(startedAt))
    }

    /// Part of the session inside `interval` (an open session counts until now).
    func overlap(with interval: DateInterval, now: Date = .now) -> TimeInterval {
        let start = max(startedAt, interval.start)
        let end = min(endedAt ?? now, interval.end)
        return max(0, end.timeIntervalSince(start))
    }

    /// Root ancestor of the session's space, used for per-root totals.
    var rootSpace: Space? {
        var current = space
        while let parent = current?.parent { current = parent }
        return current
    }
}

/// Day-bounded pieces of a time range: [22:00, 01:00) → [22:00, 00:00) + [00:00, 01:00).
enum SessionSplit {
    /// Pieces a session is closed into. A gym workout keeps its session whole, so its duration
    /// and volume stay on one session; per-day totals still split it (TimeTotals uses overlaps).
    static func closing(from start: Date, to end: Date, hasWorkout: Bool, calendar: Calendar = .app) -> [(start: Date, end: Date)] {
        guard end > start else { return [] }
        return hasWorkout ? [(start, end)] : pieces(from: start, to: end, calendar: calendar)
    }

    static func pieces(from start: Date, to end: Date, calendar: Calendar = .app) -> [(start: Date, end: Date)] {
        guard end > start else { return [] }
        var result: [(Date, Date)] = []
        var cursor = start
        while let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: cursor)),
              nextMidnight < end {
            result.append((cursor, nextMidnight))
            cursor = nextMidnight
        }
        result.append((cursor, end))
        return result
    }
}

/// Totals over a set of sessions.
enum TimeTotals {
    /// Seconds spent in `interval`, optionally restricted to a space subtree.
    static func seconds(_ sessions: [Session], in interval: DateInterval, within space: Space? = nil, now: Date = .now) -> TimeInterval {
        sessions.reduce(0) { total, session in
            if let space {
                guard let own = session.space, space.contains(own) else { return total }
            }
            return total + session.overlap(with: interval, now: now)
        }
    }

    /// Seconds per root space in `interval`, largest first.
    static func byRoot(_ sessions: [Session], in interval: DateInterval, now: Date = .now) -> [(space: Space, seconds: TimeInterval)] {
        var totals: [UUID: (Space, TimeInterval)] = [:]
        for session in sessions {
            guard let root = session.rootSpace else { continue }
            let seconds = session.overlap(with: interval, now: now)
            guard seconds > 0 else { continue }
            totals[root.id, default: (root, 0)].1 += seconds
        }
        return totals.values.map { (space: $0.0, seconds: $0.1) }.sorted { $0.seconds > $1.seconds }
    }

    static func week(containing date: Date, calendar: Calendar = .app) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: date, duration: 7 * 86_400)
    }

    static func day(containing date: Date, calendar: Calendar = .app) -> DateInterval {
        calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
    }
}

/// "45 min", "18h", "4h10".
enum TimeFormat {
    static func short(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h\(String(format: "%02d", rest))"
    }

    /// "+4h", "−1h30", "±0".
    static func delta(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        guard minutes != 0 else { return "±0" }
        let sign = minutes > 0 ? "+" : "−"
        return sign + short(TimeInterval(abs(minutes) * 60))
    }

    /// "09:00 – 11:00", "14:20 – en cours".
    static func range(_ session: Session) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute().locale(.app)
        let end = session.endedAt.map { $0.formatted(style) } ?? "en cours"
        return "\(session.startedAt.formatted(style)) – \(end)"
    }
}
