import Foundation

/// The five daily prayers.
nonisolated enum Prayer: String, Codable, CaseIterable, Identifiable, Sendable {
    case fajr
    case dhuhr
    case asr
    case maghrib
    case isha

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fajr: "Fajr"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }

    /// Dhuhr is shown as "Jumu'a" on Fridays.
    func name(on day: Date, calendar: Calendar) -> String {
        self == .dhuhr && calendar.component(.weekday, from: day) == 6 ? "Jumu'a" : name
    }

    var next: Prayer? {
        let all = Prayer.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

/// Fajr / Isha conventions. Angles are degrees below the horizon.
nonisolated enum PrayerMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case franceMuslims12
    case mwl
    case ummAlQura
    case isna
    case egypt
    case karachi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .franceMuslims12: "Musulmans de France 12°"
        case .mwl: "Ligue islamique mondiale"
        case .ummAlQura: "Umm al-Qura"
        case .isna: "ISNA"
        case .egypt: "Égypte"
        case .karachi: "Karachi"
        }
    }

    var fajrAngle: Double {
        switch self {
        case .franceMuslims12: 12
        case .mwl: 18
        case .ummAlQura: 18.5
        case .isna: 15
        case .egypt: 19.5
        case .karachi: 18
        }
    }

    /// Isha by angle, or a fixed delay after Maghrib (Umm al-Qura).
    var isha: (angle: Double?, minutesAfterMaghrib: Double?) {
        switch self {
        case .franceMuslims12: (12, nil)
        case .mwl: (17, nil)
        case .ummAlQura: (nil, 90)
        case .isna: (15, nil)
        case .egypt: (17.5, nil)
        case .karachi: (18, nil)
        }
    }
}

nonisolated enum AsrMadhab: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Shadow = object length + noon shadow (Shafi'i, Maliki, Hanbali).
    case shafi
    /// Shadow = twice the object length + noon shadow.
    case hanafi

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shafi: "Standard (Chafiite)"
        case .hanafi: "Hanafite"
        }
    }

    var shadowFactor: Double { self == .shafi ? 1 : 2 }
}

/// Times of one day, as absolute dates.
nonisolated struct PrayerTimes: Sendable, Equatable {
    var fajr: Date
    var sunrise: Date
    var dhuhr: Date
    var asr: Date
    var maghrib: Date
    var isha: Date

    func time(of prayer: Prayer) -> Date {
        switch prayer {
        case .fajr: fajr
        case .dhuhr: dhuhr
        case .asr: asr
        case .maghrib: maghrib
        case .isha: isha
        }
    }
}

/// Prayer times from the sun position, without any dependency.
/// Sun position: low-precision almanac formulas (declination and equation of time, about
/// 1 arc-minute until 2050). Each event is computed twice, the second time with the sun
/// position at the first estimate. Fajr and Isha use the method's depression angle; at high
/// latitude, when the sun never gets that low, the angle-based rule caps them at
/// angle/60 of the night. Results are rounded to the minute, then shifted by the adjustments.
nonisolated struct PrayerTimesCalculator: Sendable {
    var latitude: Double
    var longitude: Double
    var method: PrayerMethod = .franceMuslims12
    var madhab: AsrMadhab = .shafi
    /// Minutes added to each prayer (negative = earlier).
    var adjustments: [Prayer: Int] = [:]

    /// Precaution minutes of the Grande Mosquée de Paris on top of the 12° method, read on its
    /// published December 2024 calendar (Fajr earlier, Dhuhr / Maghrib / Isha later).
    static let grandeMosqueeDeParisAdjustments: [Prayer: Int] = [.fajr: -5, .dhuhr: 5, .maghrib: 2, .isha: 4]

    /// Standard refraction plus the sun's apparent radius.
    private static let horizonAngle = 0.833

    /// Times of the calendar day containing `day`, in `calendar`'s time zone.
    func times(on day: Date, calendar: Calendar) -> PrayerTimes {
        let components = calendar.dateComponents([.year, .month, .day], from: day)
        let year = components.year ?? 2000
        let month = components.month ?? 1
        let dayOfMonth = components.day ?? 1
        // Julian day at 0h UT of the civil date; events are computed in UT hours of that date.
        let julianDay = Self.julianDay(year: year, month: month, day: dayOfMonth)

        let noon = midday(julianDay: julianDay, estimate: 12 - longitude / 15)
        let sunrise = sunAngleTime(Self.horizonAngle, julianDay: julianDay, estimate: noon - 6, before: true)
        let sunset = sunAngleTime(Self.horizonAngle, julianDay: julianDay, estimate: noon + 6, before: false)
        let asr = asrTime(julianDay: julianDay, estimate: noon + 3)
        var fajr = sunAngleTime(method.fajrAngle, julianDay: julianDay, estimate: noon - 7, before: true)
        var isha: Double
        if let minutes = method.isha.minutesAfterMaghrib {
            isha = sunset + minutes / 60
        } else {
            isha = sunAngleTime(method.isha.angle ?? 17, julianDay: julianDay, estimate: noon + 7, before: false)
        }

        // High latitudes: no Fajr / Isha angle reached, or later than the safe portion.
        let night = 24 - (sunset - sunrise)
        let fajrLimit = sunrise - method.fajrAngle / 60 * night
        if fajr.isNaN || fajr < fajrLimit { fajr = fajrLimit }
        if let angle = method.isha.angle {
            let ishaLimit = sunset + angle / 60 * night
            if isha.isNaN || isha > ishaLimit { isha = ishaLimit }
        }

        let base = Self.utcStart(year: year, month: month, day: dayOfMonth)
        func date(_ hours: Double, _ prayer: Prayer?) -> Date {
            let rounded = (hours * 60).rounded() * 60
            let adjustment = Double(prayer.flatMap { adjustments[$0] } ?? 0) * 60
            return base.addingTimeInterval(rounded + adjustment)
        }
        return PrayerTimes(
            fajr: date(fajr, .fajr),
            sunrise: date(sunrise, nil),
            dhuhr: date(noon, .dhuhr),
            asr: date(asr, .asr),
            maghrib: date(sunset, .maghrib),
            isha: date(isha, .isha)
        )
    }

    // MARK: - Events (UT hours of the civil date)

    private func midday(julianDay: Double, estimate: Double) -> Double {
        var time = estimate
        for _ in 0..<2 {
            let sun = Self.sunPosition(julianDay: julianDay + time / 24)
            time = 12 - sun.equationOfTime - longitude / 15
        }
        return time
    }

    /// Time when the sun is `angle` degrees below the horizon, before or after noon.
    private func sunAngleTime(_ angle: Double, julianDay: Double, estimate: Double, before: Bool) -> Double {
        var time = estimate
        for _ in 0..<2 {
            let sun = Self.sunPosition(julianDay: julianDay + time / 24)
            let noon = 12 - sun.equationOfTime - longitude / 15
            let hourAngle = Self.hourAngle(altitude: -angle, latitude: latitude, declination: sun.declination)
            guard !hourAngle.isNaN else { return .nan }
            time = before ? noon - hourAngle : noon + hourAngle
        }
        return time
    }

    /// Asr: shadow of an object = shadowFactor × its length + its shadow at noon.
    private func asrTime(julianDay: Double, estimate: Double) -> Double {
        var time = estimate
        for _ in 0..<2 {
            let sun = Self.sunPosition(julianDay: julianDay + time / 24)
            let noon = 12 - sun.equationOfTime - longitude / 15
            let altitude = Self.degrees(atan(1 / (madhab.shadowFactor + tan(Self.radians(abs(latitude - sun.declination))))))
            let hourAngle = Self.hourAngle(altitude: altitude, latitude: latitude, declination: sun.declination)
            time = noon + hourAngle
        }
        return time
    }

    // MARK: - Astronomy

    /// Hours between noon and the moment the sun reaches `altitude` (NaN if it never does).
    private static func hourAngle(altitude: Double, latitude: Double, declination: Double) -> Double {
        let phi = radians(latitude)
        let delta = radians(declination)
        let cosH = (sin(radians(altitude)) - sin(phi) * sin(delta)) / (cos(phi) * cos(delta))
        guard (-1...1).contains(cosH) else { return .nan }
        return degrees(acos(cosH)) / 15
    }

    /// Declination (degrees) and equation of time (hours) at a Julian day.
    static func sunPosition(julianDay: Double) -> (declination: Double, equationOfTime: Double) {
        let d = julianDay - 2_451_545.0
        let g = normalized(357.529 + 0.98560028 * d, 360)
        let q = normalized(280.459 + 0.98564736 * d, 360)
        let l = normalized(q + 1.915 * sin(radians(g)) + 0.020 * sin(radians(2 * g)), 360)
        let e = 23.439 - 0.00000036 * d
        let rightAscension = normalized(degrees(atan2(cos(radians(e)) * sin(radians(l)), cos(radians(l)))) / 15, 24)
        let declination = degrees(asin(sin(radians(e)) * sin(radians(l))))
        var equation = q / 15 - rightAscension
        // Keep it within ±12 h around the wrap of q and RA.
        if equation > 12 { equation -= 24 }
        if equation < -12 { equation += 24 }
        return (declination, equation)
    }

    /// Julian day at 0h UT of a Gregorian date.
    static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = year
        var m = month
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = Double(y / 100)
        let b = 2 - a + Double(Int(a / 4))
        return Double(Int(365.25 * Double(y + 4716))) + Double(Int(30.6001 * Double(m + 1))) + Double(day) + b - 1524.5
    }

    private static func utcStart(year: Int, month: Int, day: Int) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return utc.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    private static func normalized(_ value: Double, _ range: Double) -> Double {
        let result = value.truncatingRemainder(dividingBy: range)
        return result < 0 ? result + range : result
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
