import Foundation
import Testing
@testable import RemindersInt

/// Rule-based reading of prayer sentences (the fallback parser; Foundation Models defers to it).
struct PrayerVoiceTests {
    private static let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 17, minute: 0))!
    }()

    struct Case: Sendable, CustomTestStringConvertible {
        var phrase: String
        var prayer: Prayer
        var mark: PrayerCheck.Mark
        var isYesterday: Bool

        var testDescription: String { phrase }
    }

    @Test(arguments: [
        Case(phrase: "J'ai fait dhuhr", prayer: .dhuhr, mark: .done, isYesterday: false),
        Case(phrase: "Fajr fait", prayer: .fajr, mark: .done, isYesterday: false),
        Case(phrase: "Asr en retard", prayer: .asr, mark: .late, isYesterday: false),
        Case(phrase: "J'ai rattrapé isha d'hier", prayer: .isha, mark: .madeUp, isYesterday: true),
        Case(phrase: "Sobh fait à l'heure", prayer: .fajr, mark: .onTime, isYesterday: false),
        Case(phrase: "J'ai prié le dohr", prayer: .dhuhr, mark: .done, isYesterday: false),
        Case(phrase: "Icha faite", prayer: .isha, mark: .done, isYesterday: false),
        Case(phrase: "Maghrib ok", prayer: .maghrib, mark: .done, isYesterday: false),
    ])
    func prayerSentences(_ testCase: Case) {
        let parsed = FallbackParser(now: Self.now).parse(testCase.phrase).capture
        #expect(parsed.intent == .prayerCheck)
        #expect(parsed.prayerCheck == PrayerCheck(prayer: testCase.prayer, mark: testCase.mark, isYesterday: testCase.isYesterday))
    }

    /// Not prayer ticks: a reminder about a prayer, a session log, a plain task.
    @Test(arguments: [
        "Rappelle-moi de faire asr à 16h",
        "J'ai fait 2h de maths ce matin",
        "Il faut que je fasse les courses",
    ])
    func otherSentences(_ phrase: String) {
        #expect(FallbackParser(now: Self.now).parse(phrase).capture.intent != .prayerCheck)
    }
}
