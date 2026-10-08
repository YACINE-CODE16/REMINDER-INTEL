import Foundation
import Observation
import SwiftData
import UserNotifications
import WidgetKit

/// Schedules local notifications for reminders and handles their actions.
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

    /// Set when the user taps a notification; the root view opens the matching detail.
    var reminderToOpen: UUID?

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
        center.setNotificationCategories([category])
    }

    /// iOS only shows the prompt once; later calls return the stored answer.
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    // MARK: - Scheduling

    /// Replaces the notifications of a reminder; schedules nothing unless it is pending.
    func schedule(_ reminder: Reminder) {
        cancel(reminder)
        defer { refreshWidget() }
        guard reminder.status == .pending else { return }
        for item in requests(for: reminder, after: .now) {
            center.add(item.request)
        }
    }

    /// Removes pending and delivered notifications of a reminder.
    func cancel(_ reminder: Reminder) {
        cancel(reminderID: reminder.id)
    }

    private func cancel(reminderID: UUID) {
        let identifiers = (0...Self.maxFollowUps).map { Self.identifier(for: reminderID, index: $0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Changes the status and keeps notifications in sync.
    func setStatus(_ status: ReminderStatus, for reminder: Reminder) {
        syncSentCount(for: reminder, now: .now)
        reminder.status = status
        schedule(reminder)
        try? reminder.modelContext?.save()
    }

    /// Cancels the notifications of a reminder, then deletes it from the store.
    func delete(_ reminder: Reminder) {
        cancel(reminder)
        guard let context = reminder.modelContext else { return }
        context.delete(reminder)
        try? context.save()
        refreshWidget()
    }

    /// Rebuilds every pending request from the store, keeping the 64 soonest overall.
    func rescheduleAllPending() {
        center.removeAllPendingNotificationRequests()
        let now = Date.now
        let items = pendingReminders()
            .flatMap { requests(for: $0, after: now) }
            .sorted { $0.date < $1.date }
            .prefix(Self.maxPendingRequests)
        for item in items {
            center.add(item.request)
        }
        refreshWidget()
    }

    /// Publishes the upcoming pending reminders to the lock screen widget.
    private func refreshWidget() {
        let now = Date.now
        let upcoming = pendingReminders()
            .filter { $0.dueDate > now }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(20)
            .map { WidgetSnapshot.Item(id: $0.id, title: $0.title, dueDate: $0.dueDate) }
        WidgetSnapshot(upcoming: Array(upcoming)).save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nextReminder)
    }

    /// Fire dates of the first notification and its follow-ups.
    func fireDates(for reminder: Reminder) -> [Date] {
        guard let interval = reminder.repeatInterval.duration else { return [reminder.dueDate] }
        return (0...Self.maxFollowUps).map { reminder.dueDate.addingTimeInterval(Double($0) * interval) }
    }

    private func requests(for reminder: Reminder, after now: Date) -> [(date: Date, request: UNNotificationRequest)] {
        let dates = fireDates(for: reminder)
        return dates.enumerated().compactMap { index, date in
            guard date > now else { return nil }

            let content = UNMutableNotificationContent()
            content.title = "Rappel"
            content.body = reminder.title
            if let subtitle = Self.subtitle(index: index, lastIndex: dates.count - 1, interval: reminder.repeatInterval) {
                content.subtitle = subtitle
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

    private func syncSentCount(for reminder: Reminder, now: Date) {
        guard reminder.status == .pending else { return }
        // Dates before creation were never scheduled.
        let delivered = fireDates(for: reminder).filter { $0 >= reminder.createdAt && $0 <= now }.count
        markSent(reminder, count: delivered)
    }

    private func markSent(_ reminder: Reminder, count: Int) {
        if count > reminder.remindersSent {
            reminder.remindersSent = count
        }
    }

    // MARK: - Store access

    func reminder(with id: UUID) -> Reminder? {
        guard let context = modelContainer?.mainContext else { return nil }
        var descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func pendingReminders() -> [Reminder] {
        guard let context = modelContainer?.mainContext else { return [] }
        // Enum predicates are not supported by SwiftData, filter in memory.
        let all = (try? context.fetch(FetchDescriptor<Reminder>())) ?? []
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
        guard let target, let reminder = reminder(with: target.id), reminder.status == .pending else { return }
        markSent(reminder, count: target.index + 1)
        try? reminder.modelContext?.save()
    }

    fileprivate func handleResponse(action: String, target: Target?) {
        guard let target else { return }
        let reminder = reminder(with: target.id)
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
            reminderToOpen = target.id
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
        nonisolated(unsafe) let completion = completionHandler
        Task { @MainActor in
            self.handleResponse(action: action, target: target)
            completion()
        }
    }
}
