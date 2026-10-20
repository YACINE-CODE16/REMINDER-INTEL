import Foundation
import UserNotifications

/// Keeps the pending local notifications within iOS's 64. Every service adds its requests
/// through `add`: the new requests and those already pending are ranked together and the
/// lowest ranked are dropped (never added, or removed if already pending).
@MainActor
enum NotificationBudget {
    nonisolated static let limit = 64

    /// Rank when the 64 are exceeded, highest first.
    nonisolated enum Priority: Int, Comparable, Sendable {
        /// Adhans, today's prayer follow-ups, and the one-off session / rest notifications.
        case prayerAndLive = 0
        /// First notification of reminders and tasks, nearest due date first.
        case reminder = 1
        /// Follow-ups of reminders and of prayers of other days.
        case followUp = 2
        /// "Rien tracké aujourd'hui".
        case dailyTracking = 3

        static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    nonisolated struct Candidate: Sendable, Equatable {
        var id: String
        var fireDate: Date
        var priority: Priority
    }

    /// The `limit` candidates to keep: by priority, then soonest first.
    nonisolated static func select(_ candidates: [Candidate], limit: Int = limit) -> [Candidate] {
        Array(candidates.sorted { lhs, rhs in
            lhs.priority != rhs.priority ? lhs.priority < rhs.priority : lhs.fireDate < rhs.fireDate
        }.prefix(limit))
    }

    /// Priority from the identifier schemes of the services.
    nonisolated static func priority(of identifier: String, fireDate: Date, now: Date = .now, calendar: Calendar = .current) -> Priority {
        if identifier.hasPrefix("daily-tracking-") { return .dailyTracking }
        // "prayer-20261018-asr-<k>": k = 0 adhan, k > 0 follow-up.
        if identifier.hasPrefix("prayer-") {
            let index = Int(identifier.split(separator: "-").last ?? "") ?? 0
            if index == 0 || calendar.isDate(fireDate, inSameDayAs: now) { return .prayerAndLive }
            return .followUp
        }
        // "<uuid>-<k>": task or reminder, k = 0 first notification.
        if let parsed = NotificationService.parse(identifier) {
            return parsed.index == 0 ? .reminder : .followUp
        }
        // "session-long", "gym-rest": one at a time, time-sensitive.
        return .prayerAndLive
    }

    nonisolated static func candidate(for request: UNNotificationRequest, now: Date = .now) -> Candidate {
        let fireDate = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
            ?? now
        return Candidate(id: request.identifier, fireDate: fireDate, priority: priority(of: request.identifier, fireDate: fireDate, now: now))
    }

    // MARK: - Applying

    private static var queue: [UNNotificationRequest] = []
    private static var isApplying = false
    /// Added by the previous batch: the center may not list them yet.
    private static var lastAdded: [Candidate] = []

    /// Schedules `requests` within the budget (asynchronously, in call order).
    static func add(_ requests: [UNNotificationRequest]) {
        guard !requests.isEmpty else { return }
        queue.append(contentsOf: requests)
        applyNext()
    }

    private static func applyNext() {
        guard !isApplying, !queue.isEmpty else { return }
        isApplying = true
        let batch = queue
        queue = []
        pendingCandidates { pending in
            apply(batch, pending: pending)
            isApplying = false
            applyNext()
        }
    }

    private static func apply(_ batch: [UNNotificationRequest], pending: [Candidate]) {
        let center = UNUserNotificationCenter.current()
        // A new request replaces a pending one with the same identifier.
        var latest: [String: UNNotificationRequest] = [:]
        for request in batch { latest[request.identifier] = request }
        let newCandidates = latest.values.map { candidate(for: $0) }
        let pendingIDs = Set(pending.map(\.id))
        let known = pending + lastAdded.filter { !pendingIDs.contains($0.id) && $0.fireDate > .now }
        let kept = known.filter { latest[$0.id] == nil }
        let selected = Set(select(kept + newCandidates).map(\.id))
        let dropped = kept.map(\.id).filter { !selected.contains($0) }
        if !dropped.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: dropped)
        }
        for request in latest.values where selected.contains(request.identifier) {
            center.add(request)
        }
        lastAdded = newCandidates.filter { selected.contains($0.id) }
    }

    /// Summaries of the pending requests, delivered on the main actor.
    nonisolated private static func pendingCandidates(_ completion: @escaping @MainActor @Sendable ([Candidate]) -> Void) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let candidates = requests.map { candidate(for: $0) }
            Task { @MainActor in completion(candidates) }
        }
    }
}
