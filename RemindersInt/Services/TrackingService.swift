import ActivityKit
import Foundation
import Observation
import SwiftData
import UserNotifications

/// Time tracking: one open session at a time, split at midnight, mirrored by a Live Activity.
/// Also owns the "Toujours sur … ?" notification and the 20:00 "Rien tracké aujourd'hui" reminder.
@MainActor
@Observable
final class TrackingService {
    static let shared = TrackingService()

    static let longSessionCategory = "SESSION_LONG"
    static let continueActionIdentifier = "SESSION_CONTINUE"
    static let stopActionIdentifier = "SESSION_STOP"
    private static let longSessionRequestID = "session-long"
    private static let dailyRequestPrefix = "daily-tracking-"
    /// First "Toujours sur … ?" after this, then again every `followUpDelay` if continued.
    static let longSessionDelay: TimeInterval = 4 * 3600
    private static let followUpDelay: TimeInterval = 2 * 3600
    private static let dailyReminderHour = 20

    /// Bumped when a notification asks to show the Suivi tab.
    private(set) var showTrackingRequests = 0

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    private var context: ModelContext? { container?.mainContext }

    func configure(with container: ModelContainer) {
        self.container = container
        SessionControl.stop = { [weak self] in self?.stop() }
    }

    static var notificationCategory: UNNotificationCategory {
        let keep = UNNotificationAction(
            identifier: continueActionIdentifier,
            title: "Continuer",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "play.fill")
        )
        let stop = UNNotificationAction(
            identifier: stopActionIdentifier,
            title: "Arrêter maintenant",
            options: [.destructive],
            icon: UNNotificationActionIcon(systemImageName: "stop.fill")
        )
        return UNNotificationCategory(identifier: longSessionCategory, actions: [keep, stop], intentIdentifiers: [], options: [])
    }

    // MARK: - Queries

    func activeSession() -> Session? {
        let all = (try? context?.fetch(FetchDescriptor<Session>(predicate: #Predicate { $0.endedAt == nil }))) ?? []
        return all.max { $0.startedAt < $1.startedAt }
    }

    private func sessions(in interval: DateInterval) -> [Session] {
        let start = interval.start
        let end = interval.end
        let descriptor = FetchDescriptor<Session>(predicate: #Predicate { $0.startedAt < end })
        return ((try? context?.fetch(descriptor)) ?? []).filter { ($0.endedAt ?? .now) > start }
    }

    // MARK: - Start / stop / log

    /// Starts a session now; an open one is closed first.
    @discardableResult
    func start(in space: Space, at date: Date = .now, note: String? = nil, transcript: String? = nil) -> Session? {
        guard let context else { return nil }
        stop(at: date)
        let session = Session(space: space, startedAt: date, note: note, rawTranscript: transcript)
        context.insert(session)
        try? context.save()
        startActivity(for: session)
        scheduleLongSessionReminder(for: session, at: date.addingTimeInterval(Self.longSessionDelay))
        refreshDailyReminders()
        return session
    }

    /// Closes the open session, split at midnight if needed. Returns the closed session.
    @discardableResult
    func stop(at date: Date = .now) -> Session? {
        guard let session = activeSession() else {
            endActivities()
            return nil
        }
        close(session, at: max(date, session.startedAt))
        try? context?.save()
        endActivities()
        center.removePendingNotificationRequests(withIdentifiers: [Self.longSessionRequestID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.longSessionRequestID])
        refreshDailyReminders()
        return session
    }

    /// Records a past session, one piece per day.
    @discardableResult
    func log(in space: Space, from start: Date, to end: Date, note: String? = nil, transcript: String? = nil) -> [Session] {
        guard let context else { return [] }
        let pieces = SessionSplit.pieces(from: start, to: end)
        let sessions = pieces.map {
            Session(space: space, startedAt: $0.start, endedAt: $0.end, note: note, rawTranscript: transcript)
        }
        sessions.forEach(context.insert)
        try? context.save()
        refreshDailyReminders()
        return sessions
    }

    /// Edits a session; a closed one crossing midnight is split again.
    func update(_ session: Session, space: Space, start: Date, end: Date?, note: String?) {
        session.space = space
        session.note = note
        session.startedAt = start
        if let end, !session.isActive {
            session.endedAt = start
            close(session, at: max(end, start))
        }
        try? context?.save()
        if session.isActive {
            startActivity(for: session)
            scheduleLongSessionReminder(for: session, at: max(Date.now, start.addingTimeInterval(Self.longSessionDelay)))
        }
        refreshDailyReminders()
    }

    func delete(_ session: Session) {
        let wasActive = session.isActive
        context?.delete(session)
        try? context?.save()
        if wasActive {
            endActivities()
            center.removePendingNotificationRequests(withIdentifiers: [Self.longSessionRequestID])
        }
        refreshDailyReminders()
    }

    /// Moves a just-created session to another space (the "Changer" of the capture toast).
    func move(_ sessions: [Session], to space: Space) {
        sessions.forEach { $0.space = space }
        try? context?.save()
        if let active = sessions.first(where: \.isActive) {
            startActivity(for: active)
        }
    }

    private func close(_ session: Session, at end: Date) {
        let pieces = SessionSplit.pieces(from: session.startedAt, to: end)
        guard let first = pieces.first else {
            session.endedAt = end
            return
        }
        session.endedAt = first.end
        for piece in pieces.dropFirst() {
            guard let space = session.space else { continue }
            context?.insert(Session(space: space, startedAt: piece.start, endedAt: piece.end, note: session.note))
        }
    }

    /// Launch / foreground: applies a stop requested from the Live Activity while the app was
    /// not running, then brings the Live Activity and reminders back in line with the store.
    func resume() {
        if let requested = SessionControl.takeStopRequest() {
            stop(at: requested)
        }
        if let active = activeSession() {
            startActivity(for: active)
        } else {
            endActivities()
        }
        refreshDailyReminders()
    }

    // MARK: - Live Activity

    /// Starts the activity, or updates the running one for the same session.
    /// Activities are not Sendable: tasks look them up again by id.
    private func startActivity(for session: Session) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let space = session.space else { return }
        let state = SessionActivityAttributes.ContentState(
            startedAt: session.startedAt,
            spacePath: space.pathComponents.joined(separator: " · "),
            colorHex: space.colorHex,
            symbol: space.sfSymbol
        )
        let content = ActivityContent(state: state, staleDate: nil)
        let sessionID = session.id
        let running = Activity<SessionActivityAttributes>.activities
        let others = running.filter { $0.attributes.sessionID != sessionID }.map(\.id)
        Self.end(activityIDs: others)
        if running.contains(where: { $0.attributes.sessionID == sessionID }) {
            Task {
                for activity in Activity<SessionActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
                    await activity.update(content)
                }
            }
        } else {
            _ = try? Activity.request(attributes: SessionActivityAttributes(sessionID: sessionID), content: content, pushType: nil)
        }
    }

    private func endActivities() {
        Self.end(activityIDs: Activity<SessionActivityAttributes>.activities.map(\.id))
    }

    private static func end(activityIDs: [String]) {
        guard !activityIDs.isEmpty else { return }
        Task {
            for activity in Activity<SessionActivityAttributes>.activities where activityIDs.contains(activity.id) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    // MARK: - Notifications

    private func scheduleLongSessionReminder(for session: Session, at date: Date) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.longSessionRequestID])
        guard let space = session.space else { return }
        let content = UNMutableNotificationContent()
        content.title = "Toujours sur \(space.name) ?"
        content.body = "Session en cours depuis \(TimeFormat.short(date.timeIntervalSince(session.startedAt)))."
        content.sound = .default
        content.categoryIdentifier = Self.longSessionCategory
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.longSessionRequestID, content: content, trigger: trigger))
    }

    func handleNotificationResponse(action: String) {
        switch action {
        case Self.stopActionIdentifier:
            stop()
        case Self.continueActionIdentifier:
            if let active = activeSession() {
                scheduleLongSessionReminder(for: active, at: .now.addingTimeInterval(Self.followUpDelay))
            }
        default:
            showTrackingRequests += 1
        }
    }

    func handleDailyReminderTap() {
        showTrackingRequests += 1
    }

    static func isDailyReminder(_ identifier: String) -> Bool {
        identifier.hasPrefix(dailyRequestPrefix)
    }

    /// One reminder per day at 20:00 for the next week, except today once something is tracked.
    func refreshDailyReminders(now: Date = .now) {
        let identifiers = (0..<8).map { "\(Self.dailyRequestPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        let enabled = UserDefaults.standard.object(forKey: AppStorageKey.dailyTrackingReminder) as? Bool ?? true
        guard enabled else { return }
        let calendar = Calendar.app
        let trackedToday = TimeTotals.seconds(sessions(in: TimeTotals.day(containing: now)), in: TimeTotals.day(containing: now), now: now) > 0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let fire = calendar.date(bySettingHour: Self.dailyReminderHour, minute: 0, second: 0, of: day),
                  fire > now
            else { continue }
            if offset == 0, trackedToday { continue }
            let content = UNMutableNotificationContent()
            content.title = "Rien tracké aujourd'hui"
            content.body = "Note ta journée en une phrase : « j'ai fait 2h de maths ce matin »."
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(Self.dailyRequestPrefix)\(offset)", content: content, trigger: trigger))
        }
    }
}
