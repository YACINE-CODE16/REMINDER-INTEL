import Foundation
import Testing
@testable import RemindersInt

/// Calculator against published Paris calendars, ± 3 minutes.
struct PrayerTimesCalculatorTests {
    private static let paris: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()

    private static let parisCenter = (latitude: 48.8566, longitude: 2.3522)

    /// Fajr, Dhuhr, Asr, Maghrib, Isha in Paris local time.
    private struct Reference {
        var year: Int
        var month: Int
        var day: Int
        var times: [String]
    }

    private func check(_ calculator: PrayerTimesCalculator, _ reference: Reference) {
        let calendar = Self.paris
        let day = calendar.date(from: DateComponents(year: reference.year, month: reference.month, day: reference.day, hour: 12))!
        let times = calculator.times(on: day, calendar: calendar)
        for (prayer, expected) in zip(Prayer.allCases, reference.times) {
            let parts = expected.split(separator: ":").compactMap { Int($0) }
            let expectedDate = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day)!
            let delta = times.time(of: prayer).timeIntervalSince(expectedDate) / 60
            #expect(abs(delta) <= 3, "\(reference.year)-\(reference.month)-\(reference.day) \(prayer.name): \(delta) min")
        }
    }

    /// Grande Mosquée de Paris, December 2024 calendar ("calculés par la mosquée de Paris",
    /// relayed by evous.fr). The precaution offsets were read on 1 December; these dates are
    /// independent of it.
    @Test(arguments: [
        Reference(year: 2024, month: 12, day: 5, times: ["07:07", "12:46", "14:37", "16:57", "18:15"]),
        Reference(year: 2024, month: 12, day: 20, times: ["07:18", "12:53", "14:39", "16:58", "18:18"]),
        Reference(year: 2024, month: 12, day: 25, times: ["07:20", "12:56", "14:42", "17:01", "18:20"]),
    ])
    private func grandeMosqueeDeParis(_ reference: Reference) {
        let calculator = PrayerTimesCalculator(
            latitude: Self.parisCenter.latitude,
            longitude: Self.parisCenter.longitude,
            method: .franceMuslims12,
            madhab: .shafi,
            adjustments: PrayerTimesCalculator.grandeMosqueeDeParisAdjustments
        )
        check(calculator, reference)
    }

    /// Plain 12° method (the app default), Bladi / Wadifa Paris calendar, across the switch to
    /// winter time on 25 October 2026.
    @Test(arguments: [
        Reference(year: 2026, month: 8, day: 31, times: ["05:53", "13:51", "17:36", "20:35", "21:48"]),
        Reference(year: 2026, month: 10, day: 18, times: ["07:07", "13:36", "16:26", "18:55", "20:04"]),
        Reference(year: 2026, month: 10, day: 25, times: ["06:17", "12:35", "15:15", "17:42", "18:52"]),
    ])
    private func musulmansDeFrance12(_ reference: Reference) {
        let calculator = PrayerTimesCalculator(
            latitude: Self.parisCenter.latitude,
            longitude: Self.parisCenter.longitude,
            method: .franceMuslims12,
            madhab: .shafi
        )
        check(calculator, reference)
    }

    /// Hanafi Asr is later than the standard one; MWL Fajr earlier than 12°.
    @Test func conventionsOrder() {
        let day = Self.paris.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!
        let standard = PrayerTimesCalculator(latitude: 48.8566, longitude: 2.3522).times(on: day, calendar: Self.paris)
        let hanafi = PrayerTimesCalculator(latitude: 48.8566, longitude: 2.3522, madhab: .hanafi).times(on: day, calendar: Self.paris)
        let mwl = PrayerTimesCalculator(latitude: 48.8566, longitude: 2.3522, method: .mwl).times(on: day, calendar: Self.paris)
        #expect(hanafi.asr > standard.asr)
        #expect(mwl.fajr < standard.fajr)
        #expect(mwl.isha > standard.isha)
    }

    /// Paris in June: the sun never reaches 18° below the horizon; MWL Fajr still exists.
    @Test func highLatitudeSummer() {
        let day = Self.paris.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12))!
        let times = PrayerTimesCalculator(latitude: 48.8566, longitude: 2.3522, method: .mwl).times(on: day, calendar: Self.paris)
        #expect(times.fajr < times.sunrise)
        #expect(times.isha > times.maghrib)
    }
}
