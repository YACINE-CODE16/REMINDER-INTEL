#if DEBUG
import Foundation
import SwiftData

/// "Prière" space with the module on and 20 weeks of history (`-seedDemoPrayer YES`, once):
/// a 23-day 5/5 streak up to yesterday (broken by a missed Fajr 24 days ago), Fajr missed or
/// late more often than the others, and 3 prayers left to make up (2 Fajr, 1 Isha).
enum DemoPrayer {
    /// `-resetDemoPrayer YES`: removes the prayer spaces and every prayer record first.
    @MainActor
    static func reset(in context: ModelContext) {
        for space in (try? context.fetch(FetchDescriptor<Space>())) ?? [] where space.activeModule == .prayer {
            context.delete(space)
        }
        for record in (try? context.fetch(FetchDescriptor<PrayerRecord>())) ?? [] {
            context.delete(record)
        }
        try? context.save()
    }

    @MainActor
    static func insert(into context: ModelContext, now: Date = .now) {
        let spaces = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        guard !spaces.contains(where: { $0.activeModule == .prayer }) else { return }
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: now)
        let activation = calendar.date(byAdding: .day, value: -140, to: today) ?? today

        let roots = spaces.filter { $0.parent == nil }
        let space = Space(name: "Prière", colorHex: "#0F9D8A", sfSymbol: "moon.stars.fill", sortOrder: (roots.map(\.sortOrder).max() ?? -1) + 1)
        space.module = .prayer
        context.insert(space)
        let settings = PrayerSettings(space: space, activatedAt: activation)
        settings.hasLocation = true
        context.insert(settings)

        // Deterministic pseudo-random sequence.
        var seed: UInt64 = 42
        func random() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 33) / Double(1 << 31)
        }
        let calculator = settings.calculator
        let unrecovered: Set<String> = ["24-fajr", "41-fajr", "35-isha"]

        var day = activation
        while day <= today {
            let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
            let times = calculator.times(on: day, calendar: calendar)
            for prayer in Prayer.allCases {
                let time = times.time(of: prayer)
                guard time <= now else { continue }
                let deadline = prayer.next.map { times.time(of: $0) } ?? time.addingTimeInterval(8 * 3600)
                let status: PrayerStatus
                if unrecovered.contains("\(daysAgo)-\(prayer.rawValue)") {
                    status = .missed
                } else if daysAgo <= 23 {
                    // The streak: everything done, Fajr sometimes late.
                    status = prayer == .fajr && random() < 0.2 ? .late : .onTime
                } else {
                    let roll = random()
                    let (missRate, lateRate) = prayer == .fajr ? (0.12, 0.25) : (0.03, 0.08)
                    if roll < missRate {
                        // Older misses were made up.
                        status = .madeUp
                    } else if roll < missRate + lateRate {
                        status = .late
                    } else {
                        status = .onTime
                    }
                }
                let checkedAt: Date? = switch status {
                case .onTime: time.addingTimeInterval(600)
                case .late: deadline.addingTimeInterval(1200)
                case .madeUp: calendar.date(byAdding: .day, value: 1, to: time)
                case .missed, .pending: nil
                }
                context.insert(PrayerRecord(date: day, prayer: prayer, status: status, checkedAt: checkedAt))
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
        }
        try? context.save()
    }
}
#endif
