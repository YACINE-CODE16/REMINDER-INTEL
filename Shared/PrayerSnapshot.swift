import AppIntents
import Foundation
import UserNotifications
import WidgetKit

/// Prayer times from yesterday to tomorrow, written by the app into the App Group for the
/// "Prochaine prière" widget and the "Prière faite" control (neither reads SwiftData).
nonisolated struct PrayerSnapshot: Codable, Sendable {
    struct Slot: Codable, Sendable, Identifiable {
        /// "20261018-asr", also the stem of its notification identifiers.
        var id: String
        /// Raw value of the prayer.
        var prayer: String
        /// "Asr", "Jumu'a" on Fridays.
        var name: String
        var time: Date
        /// Next prayer: ticked before it = on time.
        var deadline: Date
        /// Past this, an unticked prayer is missed (midnight, next Fajr for Isha).
        var end: Date
        var isDone: Bool
    }

    var colorHex: String
    var slots: [Slot]

    /// Next prayer to come.
    func next(after now: Date) -> Slot? {
        slots.filter { $0.time > now }.min { $0.time < $1.time }
    }

    /// Latest prayer already called, not ticked, not yet missed.
    func current(at now: Date) -> Slot? {
        slots.filter { $0.time <= now && now < $0.end && !$0.isDone }.max { $0.time < $1.time }
    }

    /// Notification identifiers of a slot: adhan (0) and follow-ups.
    static func notificationIdentifiers(of slotID: String) -> [String] {
        (0...maxFollowUps).map { "prayer-\(slotID)-\($0)" }
    }

    static let maxFollowUps = 8

    private static let storageKey = "prayerSnapshot"

    static func load() -> PrayerSnapshot? {
        guard let data = AppGroup.defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(PrayerSnapshot.self, from: data)
    }

    /// Removes the snapshot when the module is off.
    static func clear() {
        AppGroup.defaults?.removeObject(forKey: storageKey)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults?.set(data, forKey: Self.storageKey)
    }
}

/// "Prière faite" control: ticks the prayer currently due.
struct CheckPrayerIntent: AppIntent {
    static let title: LocalizedStringResource = "Prière faite"
    static let description = IntentDescription("Coche la prière en cours dans RemindersInt.")

    @MainActor
    func perform() async throws -> some IntentResult {
        let now = Date.now
        if let check = PrayerControl.check {
            check(now)
        } else {
            PrayerControl.requestCheck(at: now)
        }
        return .result()
    }
}

/// Bridge from the shared intent to the app's PrayerService.
@MainActor
enum PrayerControl {
    /// Set by the app at launch.
    static var check: ((Date) -> Void)?

    private static let requestsKey = "prayerCheckRequests"

    /// Extension side: remember the tap for the app, and update what the lock screen shows now
    /// (widget snapshot, remaining follow-ups of that prayer).
    static func requestCheck(at now: Date) {
        guard var snapshot = PrayerSnapshot.load(), let slot = snapshot.current(at: now) else { return }
        let defaults = AppGroup.defaults
        var requests = defaults?.array(forKey: requestsKey) as? [Double] ?? []
        requests.append(now.timeIntervalSince1970)
        defaults?.set(requests, forKey: requestsKey)

        if let index = snapshot.slots.firstIndex(where: { $0.id == slot.id }) {
            snapshot.slots[index].isDone = true
            snapshot.save()
        }
        let identifiers = PrayerSnapshot.notificationIdentifiers(of: slot.id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nextPrayer)
    }

    /// Taps recorded while the app could not handle them, consumed once.
    static func takeCheckRequests() -> [Date] {
        guard let defaults = AppGroup.defaults, let requests = defaults.array(forKey: requestsKey) as? [Double] else { return [] }
        defaults.removeObject(forKey: requestsKey)
        return requests.map { Date(timeIntervalSince1970: $0) }
    }
}
