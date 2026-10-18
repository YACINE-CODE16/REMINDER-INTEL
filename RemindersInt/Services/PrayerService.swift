import Foundation
import Observation
import SwiftData
import UserNotifications
import WidgetKit

/// Display state of one prayer of one day.
enum PrayerSlotState: Equatable {
    case onTime
    case late
    case madeUp
    case missed
    /// Called, not ticked yet, still within its day.
    case toDo
    /// The next prayer to come.
    case next
    case upcoming

    var isDone: Bool { self == .onTime || self == .late || self == .madeUp }
}

struct PrayerSlot: Identifiable {
    var day: Date
    var prayer: Prayer
    var name: String
    var time: Date
    /// Ticked before this (the next prayer) = on time.
    var deadline: Date
    /// Unticked past this = missed (midnight; next Fajr for Isha).
    var end: Date
    var state: PrayerSlotState

    var id: String { PrayerService.slotID(day: day, prayer: prayer) }
}

/// How a tick should be recorded.
enum PrayerMark: Sendable {
    /// On time or late depending on when it is ticked.
    case auto
    case onTime
    case late
    case madeUp
}

/// Prayer module: times, ticks and their automatic status, stats, adhan notifications with
/// follow-ups, and the snapshot read by the widget and the control.
@MainActor
@Observable
final class PrayerService {
    static let shared = PrayerService()

    static let categoryIdentifier = "PRAYER"
    static let doneActionIdentifier = "PRAYER_DONE"
    nonisolated private static let identifierPrefix = "prayer-"
    /// Notifications the module may keep pending, out of the 64 iOS allows.
    static let notificationBudget = 24

    /// Bumped when something should show the prayer space (notification or widget tap).
    private(set) var showPrayerSpaceRequests = 0
    /// Bumped on every change so views relying on computed times refresh.
    private(set) var revision = 0

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    private var context: ModelContext? { container?.mainContext }
    private var calendar: Calendar { .app }

    func configure(with container: ModelContainer) {
        self.container = container
        PrayerControl.check = { [weak self] date in self?.checkCurrent(at: date) }
    }

    static var notificationCategory: UNNotificationCategory {
        let done = UNNotificationAction(
            identifier: doneActionIdentifier,
            title: "Fait",
            options: [],
            icon: UNNotificationActionIcon(systemImageName: "checkmark")
        )
        return UNNotificationCategory(identifier: categoryIdentifier, actions: [done], intentIdentifiers: [], options: [])
    }

    // MARK: - Module

    /// Settings of the space running the prayer module (one at a time).
    func settings() -> PrayerSettings? {
        let all = (try? context?.fetch(FetchDescriptor<PrayerSettings>())) ?? []
        return all.first { ($0.space?.activeModule == .prayer) && !($0.space?.isArchived ?? true) }
    }

    var isActive: Bool { settings() != nil }

    /// The space already running the prayer module, if any.
    func prayerSpace() -> Space? { settings()?.space }

    /// Switches the module on for `space`, keeping earlier settings if it had some.
    @discardableResult
    func activate(on space: Space, now: Date = .now) -> PrayerSettings? {
        guard let context else { return nil }
        space.module = .prayer
        let settings = space.prayerSettings ?? {
            let created = PrayerSettings(space: space, activatedAt: calendar.startOfDay(for: now))
            context.insert(created)
            return created
        }()
        try? context.save()
        refresh(now: now)
        return settings
    }

    func deactivate(_ space: Space) {
        space.module = SpaceModule.none
        try? context?.save()
        refresh()
    }

    // MARK: - Times and slots

    func times(on day: Date, settings: PrayerSettings) -> PrayerTimes {
        settings.calculator.times(on: day, calendar: calendar)
    }

    nonisolated static func slotID(day: Date, prayer: Prayer) -> String {
        "\(dayKey(day))-\(prayer.rawValue)"
    }

    /// "20261018", in the device time zone.
    nonisolated static func dayKey(_ day: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d%02d%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func nextDay(_ day: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
    }

    /// The five prayers of `day` with their state at `now`.
    func slots(on day: Date, settings: PrayerSettings, records: [PrayerRecord], now: Date = .now) -> [PrayerSlot] {
        let start = calendar.startOfDay(for: day)
        let times = times(on: start, settings: settings)
        let tomorrowFajr = self.times(on: nextDay(start), settings: settings).fajr
        let byPrayer = Dictionary(records.filter { calendar.isDate($0.date, inSameDayAs: start) }.map { ($0.prayer, $0) }, uniquingKeysWith: { first, _ in first })
        let nextTime = nextPrayer(after: now, settings: settings)?.time

        return Prayer.allCases.map { prayer in
            let time = times.time(of: prayer)
            let deadline = prayer.next.map { times.time(of: $0) } ?? tomorrowFajr
            let end = prayer == .isha ? tomorrowFajr : nextDay(start)
            let state: PrayerSlotState
            switch byPrayer[prayer]?.status {
            case .onTime: state = .onTime
            case .late: state = .late
            case .madeUp: state = .madeUp
            case .missed: state = .missed
            case .pending, nil:
                if now >= end {
                    state = .missed
                } else if time <= now {
                    state = .toDo
                } else if time == nextTime {
                    state = .next
                } else {
                    state = .upcoming
                }
            }
            return PrayerSlot(day: start, prayer: prayer, name: prayer.name(on: start, calendar: calendar), time: time, deadline: deadline, end: end, state: state)
        }
    }

    /// Next prayer to be called after `now`, today or tomorrow.
    func nextPrayer(after now: Date, settings: PrayerSettings) -> (day: Date, prayer: Prayer, time: Date)? {
        for offset in 0...1 {
            let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
            let times = times(on: day, settings: settings)
            if let prayer = Prayer.allCases.first(where: { times.time(of: $0) > now }) {
                return (day, prayer, times.time(of: prayer))
            }
        }
        return nil
    }

    // MARK: - Records

    func records(from start: Date? = nil) -> [PrayerRecord] {
        let all: [PrayerRecord]
        if let start {
            all = (try? context?.fetch(FetchDescriptor<PrayerRecord>(predicate: #Predicate { $0.date >= start }))) ?? []
        } else {
            all = (try? context?.fetch(FetchDescriptor<PrayerRecord>())) ?? []
        }
        return all
    }

    private func record(day: Date, prayer: Prayer) -> PrayerRecord? {
        let start = calendar.startOfDay(for: day)
        let end = nextDay(start)
        let sameDay = (try? context?.fetch(FetchDescriptor<PrayerRecord>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        return sameDay.first { $0.prayer == prayer }
    }

    /// Ticks a prayer. `.auto`: on time before the next prayer, late after; a missed prayer
    /// ticked again becomes made up.
    @discardableResult
    func check(_ prayer: Prayer, on day: Date, at date: Date = .now, mark: PrayerMark = .auto) -> PrayerRecord? {
        guard let context, let settings = settings() else { return nil }
        let start = calendar.startOfDay(for: day)
        let slot = slots(on: start, settings: settings, records: records(from: start), now: date).first { $0.prayer == prayer }
        let existing = record(day: start, prayer: prayer)
        let status: PrayerStatus
        switch mark {
        case .madeUp:
            status = .madeUp
        case .onTime:
            status = .onTime
        case .late:
            status = .late
        case .auto:
            if existing?.status == .missed || slot?.state == .missed {
                status = .madeUp
            } else if let slot, date >= slot.deadline {
                status = .late
            } else {
                status = .onTime
            }
        }
        let record = existing ?? {
            let created = PrayerRecord(date: start, prayer: prayer, status: status)
            context.insert(created)
            return created
        }()
        record.status = status
        record.checkedAt = date
        try? context.save()
        refresh()
        return record
    }

    /// Unticks: back to "à faire", or missed once its day is over.
    func uncheck(_ prayer: Prayer, on day: Date) {
        guard let record = record(day: day, prayer: prayer) else { return }
        context?.delete(record)
        try? context?.save()
        refresh()
    }

    /// Control and notification "Fait": the latest prayer called, not ticked, not missed.
    func checkCurrent(at date: Date = .now) {
        guard let settings = settings() else { return }
        let today = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let all = records(from: yesterday)
        let candidates = (slots(on: yesterday, settings: settings, records: all, now: date) + slots(on: today, settings: settings, records: all, now: date))
            .filter { $0.state == .toDo }
        guard let current = candidates.max(by: { $0.time < $1.time }) else { return }
        check(current.prayer, on: current.day, at: date)
    }

    /// Days since activation (two months at most) whose unticked prayers are over become missed.
    func closePastDays(now: Date = .now) {
        guard let context, let settings = settings() else { return }
        let today = calendar.startOfDay(for: now)
        let floor = calendar.date(byAdding: .day, value: -60, to: today) ?? today
        var day = max(calendar.startOfDay(for: settings.activatedAt), floor)
        let existing = records(from: day)
        var changed = false
        while day <= today {
            for slot in slots(on: day, settings: settings, records: existing, now: now) where slot.state == .missed {
                if !existing.contains(where: { $0.prayer == slot.prayer && calendar.isDate($0.date, inSameDayAs: day) }) {
                    context.insert(PrayerRecord(date: day, prayer: slot.prayer, status: .missed))
                    changed = true
                }
            }
            day = nextDay(day)
        }
        if changed { try? context.save() }
    }

    /// Launch / foreground: ticks done from the control while the app was not running,
    /// missed prayers, notifications and widget.
    func resume(now: Date = .now) {
        for date in PrayerControl.takeCheckRequests() {
            checkCurrent(at: date)
        }
        refresh(now: now)
    }

    /// Rebuilds everything derived from the store.
    func refresh(now: Date = .now) {
        closePastDays(now: now)
        scheduleNotifications(now: now)
        writeSnapshot(now: now)
        revision += 1
    }

    // MARK: - Stats

    struct Stats {
        /// Consecutive days at 5/5, today included once complete.
        var streak: Int
        /// Prayers done / prayers called this month (since activation).
        var monthRatio: Double?
        var toMakeUp: [Prayer: Int]
        /// Lowest on-time rate over the last 30 days.
        var mostMissed: (prayer: Prayer, onTimeRatio: Double)?
        /// Done prayers per day, 0...1 (count / 5).
        var dailyValues: [Date: Double]

        var toMakeUpTotal: Int { toMakeUp.values.reduce(0, +) }
    }

    func stats(settings: PrayerSettings, records all: [PrayerRecord], now: Date = .now) -> Stats {
        let today = calendar.startOfDay(for: now)
        let activation = calendar.startOfDay(for: settings.activatedAt)
        var doneByDay: [Date: Int] = [:]
        for record in all where record.status.isDone {
            doneByDay[calendar.startOfDay(for: record.date), default: 0] += 1
        }

        var streak = 0
        var day = doneByDay[today] == 5 ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while doneByDay[day] == 5 {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }

        // Prayers already called today.
        let todayTimes = times(on: today, settings: settings)
        let calledToday = Prayer.allCases.filter { todayTimes.time(of: $0) <= now }

        func called(from start: Date) -> (total: Int, perPrayer: [Prayer: Int]) {
            let first = max(start, activation)
            let fullDays = max(0, calendar.dateComponents([.day], from: first, to: today).day ?? 0)
            var perPrayer: [Prayer: Int] = [:]
            for prayer in Prayer.allCases {
                perPrayer[prayer] = fullDays + (first <= today && calledToday.contains(prayer) ? 1 : 0)
            }
            return (perPrayer.values.reduce(0, +), perPrayer)
        }

        let monthStart = calendar.startOfMonth(for: today)
        let monthCalled = called(from: monthStart).total
        let monthDone = all.filter { $0.status.isDone && $0.date >= max(monthStart, activation) }.count
        let monthRatio = monthCalled > 0 ? min(1, Double(monthDone) / Double(monthCalled)) : nil

        var toMakeUp: [Prayer: Int] = [:]
        for record in all where record.status == .missed {
            toMakeUp[record.prayer, default: 0] += 1
        }

        let windowStart = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let window = called(from: windowStart).perPrayer
        var mostMissed: (Prayer, Double)?
        for prayer in Prayer.allCases {
            guard let total = window[prayer], total > 0 else { continue }
            let onTime = all.filter { $0.prayer == prayer && $0.status == .onTime && $0.date >= max(windowStart, activation) }.count
            let ratio = Double(onTime) / Double(total)
            if mostMissed == nil || ratio < mostMissed!.1 { mostMissed = (prayer, ratio) }
        }

        var values: [Date: Double] = [:]
        var cursor = activation
        while cursor <= today {
            values[cursor] = Double(doneByDay[cursor] ?? 0) / 5
            cursor = nextDay(cursor)
        }
        return Stats(
            streak: streak,
            monthRatio: monthRatio,
            toMakeUp: toMakeUp,
            mostMissed: mostMissed.map { (prayer: $0.0, onTimeRatio: $0.1) },
            dailyValues: values
        )
    }

    // MARK: - Notifications

    /// Adhan of each coming prayer and, until it is ticked, follow-ups up to the next prayer.
    /// Within `notificationBudget`: the adhans of the next two days first (so every prayer is
    /// announced even if the app stays closed), then the soonest follow-ups.
    private func scheduleNotifications(now: Date) {
        let today = calendar.startOfDay(for: now)
        let window = (-1...3).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        // Identifiers are deterministic: clear every one this module may have scheduled.
        let stale = window.flatMap { day in Prayer.allCases.flatMap { PrayerSnapshot.notificationIdentifiers(of: Self.slotID(day: day, prayer: $0)) } }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        guard let settings = settings(), settings.notifyAtAdhan || settings.repeatUntilDone else { return }

        let all = records(from: window[0])
        var adhans: [(Date, UNNotificationRequest)] = []
        var followUps: [(Date, UNNotificationRequest)] = []
        for day in window {
            for slot in slots(on: day, settings: settings, records: all, now: now) where !slot.state.isDone && slot.state != .missed {
                var fires: [Date] = []
                if settings.notifyAtAdhan { fires.append(slot.time) }
                if settings.repeatUntilDone, let interval = settings.repeatInterval.duration {
                    for index in 1...PrayerSnapshot.maxFollowUps {
                        let date = slot.time.addingTimeInterval(Double(index) * interval)
                        guard date < slot.deadline else { break }
                        fires.append(date)
                    }
                }
                let lastIndex = fires.count - 1
                for (index, fire) in fires.enumerated() where fire > now {
                    let followUpIndex = settings.notifyAtAdhan ? index : index + 1
                    let item = (fire, request(for: slot, fire: fire, index: followUpIndex, lastIndex: lastIndex, settings: settings))
                    if followUpIndex == 0 { adhans.append(item) } else { followUps.append(item) }
                }
            }
        }
        let horizon = now.addingTimeInterval(48 * 3600)
        let kept = adhans.filter { $0.0 <= horizon }.sorted { $0.0 < $1.0 }.prefix(10)
        let remaining = Self.notificationBudget - kept.count
        let others = (followUps + adhans.filter { $0.0 > horizon }).sorted { $0.0 < $1.0 }.prefix(max(0, remaining))
        for (_, request) in kept + others {
            center.add(request)
        }
    }

    /// `identifierIndex`: suffix of the identifier when it differs from the follow-up index (tests).
    private func request(for slot: PrayerSlot, fire: Date, index: Int, lastIndex: Int, settings: PrayerSettings, identifierIndex: Int? = nil) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "\(slot.name) · \(slot.time.formatted(.dateTime.hour().minute().locale(.app)))"
        content.body = "Il est l'heure de la prière"
        if index > 0, let subtitle = NotificationService.subtitle(index: index, lastIndex: lastIndex, interval: settings.repeatInterval) {
            content.subtitle = subtitle
        }
        content.sound = settings.quietMode ? nil : .default
        content.categoryIdentifier = Self.categoryIdentifier
        content.threadIdentifier = "prayer"
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
        return UNNotificationRequest(
            identifier: "\(Self.identifierPrefix)\(slot.id)-\(identifierIndex ?? index)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    #if DEBUG
    /// `-prayerNotificationTest YES`: the adhan of the prayer due (or next) in 5 s and its first
    /// follow-up 15 s later, through the same request builder, so the flow can be checked on
    /// the simulator without waiting for a real prayer time.
    func scheduleTestNotifications(now: Date = .now) {
        guard let settings = settings() else { return }
        let today = calendar.startOfDay(for: now)
        let slots = slots(on: today, settings: settings, records: records(from: today), now: now)
        guard let slot = slots.first(where: { $0.state == .toDo }) ?? slots.first(where: { $0.state == .next }) ?? slots.last else { return }
        // Suffixes 90 / 91: outside the range `scheduleNotifications` clears, same prayer for "Fait".
        center.add(request(for: slot, fire: now.addingTimeInterval(5), index: 0, lastIndex: 2, settings: settings, identifierIndex: 90))
        center.add(request(for: slot, fire: now.addingTimeInterval(20), index: 1, lastIndex: 2, settings: settings, identifierIndex: 91))
        print("PRAYER TEST: \(slot.name) \(slot.time.formatted(.dateTime.hour().minute())) adhan in 5 s, follow-up in 20 s")
    }

    /// Prints the pending prayer requests (identifier, title, subtitle, fire date).
    nonisolated static func logPendingRequests() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let prayer = pending.filter { isPrayerNotification($0.identifier) }
        print("PRAYER PENDING: \(prayer.count) / \(pending.count) requests")
        for request in prayer.sorted(by: { $0.identifier < $1.identifier }) {
            let next = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            print("  \(request.identifier) | \(request.content.title) | \(request.content.subtitle) | \(next.map { $0.formatted(.dateTime.day().hour().minute().second()) } ?? "?") | sound: \(request.content.sound != nil)")
        }
    }
    #endif

    nonisolated static func isPrayerNotification(_ identifier: String) -> Bool {
        identifier.hasPrefix(identifierPrefix)
    }

    /// "prayer-20261018-asr-2" → (day, asr).
    private func slot(fromNotification identifier: String) -> (day: Date, prayer: Prayer)? {
        let parts = identifier.split(separator: "-")
        guard parts.count >= 3, let prayer = Prayer(rawValue: String(parts[2])) else { return nil }
        let key = String(parts[1])
        guard key.count == 8, let year = Int(key.prefix(4)), let month = Int(key.dropFirst(4).prefix(2)), let day = Int(key.suffix(2)),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else { return nil }
        return (date, prayer)
    }

    func handleNotificationResponse(action: String, identifier: String) {
        guard let slot = slot(fromNotification: identifier) else { return }
        switch action {
        case Self.doneActionIdentifier:
            check(slot.prayer, on: slot.day)
            let ids = PrayerSnapshot.notificationIdentifiers(of: Self.slotID(day: slot.day, prayer: slot.prayer))
            center.removeDeliveredNotifications(withIdentifiers: ids + [identifier])
        default:
            showPrayerSpaceRequests += 1
        }
    }

    // MARK: - Widget

    private func writeSnapshot(now: Date) {
        guard let settings = settings() else {
            PrayerSnapshot.clear()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nextPrayer)
            return
        }
        let today = calendar.startOfDay(for: now)
        let days = (-1...1).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let all = records(from: days[0])
        let snapshotSlots = days.flatMap { slots(on: $0, settings: settings, records: all, now: now) }.map {
            PrayerSnapshot.Slot(id: $0.id, prayer: $0.prayer.rawValue, name: $0.name, time: $0.time, deadline: $0.deadline, end: $0.end, isDone: $0.state.isDone)
        }
        PrayerSnapshot(colorHex: settings.space?.colorHex ?? SpaceModule.prayer.colorHex ?? "#0F9D8A", slots: snapshotSlots).save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.nextPrayer)
    }
}
