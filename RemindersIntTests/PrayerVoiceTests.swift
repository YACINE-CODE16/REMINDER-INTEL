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

/// Step 8b: parsing follows the device's time zone.
struct ParsingTimeZoneTests {
    @Test func parsingCalendarIsTheCurrentTimeZone() {
        #expect(Calendar.parsing.timeZone == TimeZone.current)
        #expect(FallbackParser(now: .now).calendar.timeZone == TimeZone.current)
    }

    /// "Rappelle-moi à 16h" read in Algiers is 16:00 Algiers time (15:00 UTC), not Paris time.
    @Test func reminderAtFourInAlgiers() throws {
        var algiers = Calendar(identifier: .gregorian)
        algiers.locale = Locale(identifier: "fr_FR")
        algiers.timeZone = try #require(TimeZone(identifier: "Africa/Algiers"))
        algiers.firstWeekday = 2
        // 10:00 in Algiers on 18 October 2026 (Paris is UTC+2 that day, Algiers UTC+1).
        let now = try #require(algiers.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 10)))
        let parsed = FallbackParser(now: now, calendar: algiers).parse("Rappelle-moi à 16h").capture
        let due = try #require(parsed.dueDate)
        let local = algiers.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        #expect(local.hour == 16 && local.minute == 0 && local.day == 18)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(utc.component(.hour, from: due) == 15)
    }
}
