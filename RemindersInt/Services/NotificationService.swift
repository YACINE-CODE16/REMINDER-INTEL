import Foundation
import Observation
import SwiftData
import UserNotifications
import WidgetKit

/// Schedules local notifications for tasks and handles their actions.
/// Reminder tasks repeat until done; plain tasks get one notification at their due date.
@Observable
final class NotificationService: NSObject {
    static let shared = NotificationService()

    static let categoryIdentifier = "REMINDER"
    static let doneActionIdentifier = "DONE"
    static let cancelActionIdentifier = "CANCEL"
    /// Follow-ups per reminder, bounded to stay under the iOS limit of 64 pending notifications.
    static let maxFollowUps = 20
    nonisolated static let reminderIDKey = "reminderID"
    nonisolated static let indexKey = "index"
    private static let maxPendingRequests = 64
    /// Kept free for the tracking reminders ("Toujours sur … ?" and the 7 evening reminders).
    private static let trackingReserve = 10

    /// Set when the user taps a notification; the root view opens the matching detail.
    var taskToOpen: UUID?
    /// Last known notification permission (the day view shows a banner when denied).
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    // MARK: - Setup

    /// Must run before the app finishes launching so notification actions reach the delegate.
    func configure(with container: ModelContainer) {
        modelContainer = container
        center.delegate = self

        let cancel = UNNotificationAction(
            identifier: Self.cancelActionIdentifier,
            title: "Annuler",
            options: [.destructive],
            icon: UNNotificationActionIcon(systemImageName: "xmark")
        )
        let done = UNNotificationAction(
            identifier: Self.doneActionIdentifier,
            title: "Fait",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "checkmark")
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [cancel, done],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category, TrackingService.notificationCategory, PrayerService.notificationCategory])
    }

    /// iOS only shows the prompt once; later calls return the stored answer.
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorized || authorizationStatus == .provisional || authorizationStatus == .ephemeral
    }

    /// Reads the permission again; true when it just became authorized (granted in Réglages
    /// while the app was away), so everything must be scheduled again.
    @discardableResult
    func refreshAuthorizationStatus() async -> Bool {
        let wasAuthorized = isAuthorized
        let wasKnown = authorizationStatus != .notDetermined
        authorizationStatus = await Self.currentAuthorizationStatus()
        return wasKnown && !wasAuthorized && isAuthorized
    }

    nonisolated private static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    // MARK: - Scheduling

    /// Replaces the notifications of a task; schedules nothing unless it is pending and dated.
    func schedule(_ reminder: TaskItem) {
        cancel(reminder)
        defer { refreshWidget() }
        guard reminder.status == .pending else { return }
        NotificationBudget.add(requests(for: reminder, after: .now).map(\.request))
    }

    /// Removes pending and delivered notifications of a task.
    func cancel(_ reminder: TaskItem) {
        cancel(reminderID: reminder.id)
    }

    private func cancel(reminderID: UUID) {
        let identifiers = (0...Self.maxFollowUps).map { Self.identifier(for: reminderID, index: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Changes the status and keeps notifications in sync.
    func setStatus(_ status: ReminderStatus, for reminder: TaskItem) {
        syncSentCount(for: reminder, now: .now)
        reminder.status = status
        schedule(reminder)
        try? reminder.modelContext?.save()
    }

    /// Cancels the notifications of a task, then deletes it from the store.
    func delete(_ reminder: TaskItem) {
        cancel(reminder)
        guard let context = reminder.modelContext else { return }
        context.delete(reminder)
        try? context.save()
        refreshWidget()
    }

    /// Rebuilds the task requests from the store, soonest first, within what iOS allows once
    /// the tracking and prayer notifications are counted. Only task identifiers are removed:
    /// the other services keep theirs.
    func rescheduleAllPending() {
        let all = (try? modelContainer?.mainContext.fetch(FetchDescriptor<TaskItem>())) ?? []
        center.removePendingNotificationRequests(withIdentifiers: all.flatMap { task in
            (0...Self.maxFollowUps).map { Self.identifier(for: task.id, index: $0) }
        })
        let now = Date.now
        let budget = Self.maxPendingRequests - Self.trackingReserve - (PrayerService.shared.isActive ? PrayerService.notificationBudget : 0)
        let items = pendingReminders()
            .flatMap { requests(for: $0, after: now) }
            .sorted { $0.date < $1.date }
            .prefix(budget)
        NotificationBudget.add(items.map(\.request))
        refreshWidget()
    }

    /// Publishes the upcoming pending dated items, reminders and tasks, to the lock screen widget.
    private func refreshWidget() {
        let now = Date.now
        let upcoming = pendingReminders()
            .compactMap { task in task.dueDate.map { (task, $0) } }
            .filter { $0.1 > now }
            .sorted { $0.1 < $1.1 }
            .prefix(20)
            .map { WidgetSnapshot.Item(id: $0.0.id, title: $0.0.title, dueDate: $0.1, isReminder: $0.0.isReminder) }
        WidgetSnapshot(upcoming: Array(upcoming)).save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nextReminder)
    }

    /// Fire dates of the first notification and, for reminders, its follow-ups.
    func fireDates(for reminder: TaskItem) -> [Date] {
        guard let dueDate = reminder.dueDate else { return [] }
        guard reminder.isReminder, let interval = reminder.repeatInterval.duration else { return [dueDate] }
        return (0...Self.maxFollowUps).map { dueDate.addingTimeInterval(Double($0) * interval) }
    }

    private func requests(for reminder: TaskItem, after now: Date) -> [(date: Date, request: UNNotificationRequest)] {
        let dates = fireDates(for: reminder)
        return dates.enumerated().compactMap { index, date in
            guard date > now else { return nil }

            let content = UNMutableNotificationContent()
            content.title = reminder.isReminder ? "Rappel" : "Tâche"
            content.body = reminder.title
            if reminder.isReminder {
                if let subtitle = Self.subtitle(index: index, lastIndex: dates.count - 1, interval: reminder.repeatInterval) {
                    content.subtitle = subtitle
                }
            } else if let space = reminder.space {
                content.subtitle = space.displayPath
            }
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = [Self.reminderIDKey: reminder.id.uuidString, Self.indexKey: index]

            let components = Calendar.app.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifier(for: reminder.id, index: index),
                content: content,
                trigger: trigger
            )
            return (date, request)
        }
    }

    /// "Prochaine relance dans 15 min", "2e relance · prochaine dans 15 min", "20e relance · dernière".
    static func subtitle(index: Int, lastIndex: Int, interval: RepeatInterval) -> String? {
        guard interval != .none else { return nil }
        let next = "prochaine dans \(interval.shortLabel)"
        guard index > 0 else { return "Prochaine relance dans \(interval.shortLabel)" }
        let ordinal = index == 1 ? "1re" : "\(index)e"
        return "\(ordinal) relance · \(index < lastIndex ? next : "dernière")"
    }

    // MARK: - Sent counter

    /// Catches up on notifications delivered while the app was closed: every scheduled
    /// fire date already passed counts as delivered. Idempotent, safe to call often.
    func syncSentCounts() {
        let now = Date.now
        for reminder in pendingReminders() {
            syncSentCount(for: reminder, now: now)
        }
        try? modelContainer?.mainContext.save()
    }

    private func syncSentCount(for reminder: TaskItem, now: Date) {
        guard reminder.status == .pending else { return }
        // Dates before creation were never scheduled.
        let delivered = fireDates(for: reminder).filter { $0 >= reminder.createdAt && $0 <= now }.count
        markSent(reminder, count: delivered)
    }

    private func markSent(_ reminder: TaskItem, count: Int) {
        if count > reminder.remindersSent {
            reminder.remindersSent = count
        }
    }

    // MARK: - Store access

    func task(with id: UUID) -> TaskItem? {
        guard let context = modelContainer?.mainContext else { return nil }
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Pending tasks, reminders or not.
    private func pendingReminders() -> [TaskItem] {
        guard let context = modelContainer?.mainContext else { return [] }
        // Enum predicates are not supported by SwiftData, filter in memory.
        let all = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        return all.filter { $0.status == .pending }
    }

    // MARK: - Identifiers

    nonisolated static func identifier(for id: UUID, index: Int) -> String {
        "\(id.uuidString)-\(index)"
    }

    nonisolated static func parse(_ identifier: String) -> (id: UUID, index: Int)? {
        guard let dash = identifier.lastIndex(of: "-"),
              let id = UUID(uuidString: String(identifier[..<dash])),
              let index = Int(identifier[identifier.index(after: dash)...])
        else { return nil }
        return (id, index)
    }

    // MARK: - Delegate handling

    typealias Target = (id: UUID, index: Int)

    /// Reads the reminder id from userInfo, falling back to the request identifier "<uuid>-<k>".
    nonisolated static func target(of notification: UNNotification) -> Target? {
        let userInfo = notification.request.content.userInfo
        if let idString = userInfo[reminderIDKey] as? String, let id = UUID(uuidString: idString) {
            return (id, userInfo[indexKey] as? Int ?? 0)
        }
        return parse(notification.request.identifier)
    }

    fileprivate func recordDelivery(of target: Target?) {
        guard let target, let reminder = task(with: target.id), reminder.status == .pending else { return }
        markSent(reminder, count: target.index + 1)
        try? reminder.modelContext?.save()
    }

    fileprivate func handleResponse(action: String, target: Target?) {
        guard let target else { return }
        let reminder = task(with: target.id)
        if let reminder, reminder.status == .pending {
            markSent(reminder, count: target.index + 1)
        }
        switch action {
        case Self.doneActionIdentifier, Self.cancelActionIdentifier:
            if let reminder {
                setStatus(action == Self.doneActionIdentifier ? .done : .cancelled, for: reminder)
            } else {
                // Reminder deleted meanwhile: just clear its leftover notifications.
                cancel(reminderID: target.id)
            }
        case UNNotificationDefaultActionIdentifier:
            // The root view opens the detail, or stays on the day view if the reminder is gone.
            taskToOpen = target.id
        default:
            break
        }
        try? modelContainer?.mainContext.save()
    }
}

// The completion-handler variants are used on purpose. With the async variants, the
// compiler-generated @objc thunk calls UIKit's completion handler from the Swift
// concurrency pool once the method returns; UIKit asserts it runs on the main thread
// and aborts the app (crash on notification tap). Here the handler is always called
// on the main actor.
extension NotificationService: UNUserNotificationCenterDelegate {
    /// Shows notifications while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // The rest bar is on screen: no banner for the end of rest while the app is open.
        if notification.request.identifier == GymService.restNotificationID {
            completionHandler([])
            return
        }
        let target = Self.target(of: notification)
        // UIKit's handler is not annotated Sendable; it is called exactly once, on the main actor.
        nonisolated(unsafe) let completion = completionHandler
        Task { @MainActor in
            self.recordDelivery(of: target)
            completion([.banner, .list, .sound])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let target = Self.target(of: response.notification)
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let identifier = response.notification.request.identifier
        nonisolated(unsafe) let completion = completionHandler
        Task { @MainActor in
            if category == TrackingService.longSessionCategory {
                TrackingService.shared.handleNotificationResponse(action: action)
            } else if PrayerService.isPrayerNotification(identifier) {
                PrayerService.shared.handleNotificationResponse(action: action, identifier: identifier)
            } else if TrackingService.isDailyReminder(identifier) {
                TrackingService.shared.handleDailyReminderTap()
            } else {
                self.handleResponse(action: action, target: target)
            }
            completion()
        }
    }
}
