import Foundation
import SwiftData
import SwiftUI

/// Dedicated screen and structured data a space can switch on, on top of its tasks, time and goals.
nonisolated enum SpaceModule: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case prayer
    /// Step 7b.
    case gym

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Aucun"
        case .prayer: "Prière"
        case .gym: "Salle de sport"
        }
    }

    /// Default space colour and symbol when the module is switched on at creation.
    var colorHex: String? {
        switch self {
        case .prayer: "#0F9D8A"
        case .none, .gym: nil
        }
    }

    var symbol: String? {
        switch self {
        case .prayer: "moon.stars.fill"
        case .none, .gym: nil
        }
    }

    /// Modules that exist in this build (gym comes with step 7b).
    static let available: [SpaceModule] = [.none, .prayer]
}

extension Space {
    /// `module` is optional in the store so adding it was a lightweight migration.
    var activeModule: SpaceModule { module ?? .none }
}

nonisolated enum PrayerStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case onTime
    case late
    case missed
    case madeUp

    var isDone: Bool { self == .onTime || self == .late || self == .madeUp }
}

/// Prayer module settings of a space.
@Model
final class PrayerSettings {
    @Attribute(.unique) var id: UUID
    var space: Space?
    var latitude: Double
    var longitude: Double
    var cityName: String
    /// False until CoreLocation or the city search gave a place (Paris is used meanwhile).
    var hasLocation: Bool
    var method: PrayerMethod
    var asrMadhab: AsrMadhab
    var fajrAdjustment: Int
    var dhuhrAdjustment: Int
    var asrAdjustment: Int
    var maghribAdjustment: Int
    var ishaAdjustment: Int
    var notifyAtAdhan: Bool
    var repeatUntilDone: Bool
    var repeatInterval: RepeatInterval
    /// Notifications without sound.
    var quietMode: Bool
    /// Days before this one are never marked missed.
    var activatedAt: Date

    static let paris = (latitude: 48.8566, longitude: 2.3522, name: "Paris")

    init(space: Space, activatedAt: Date = .now) {
        self.id = UUID()
        self.space = space
        self.latitude = Self.paris.latitude
        self.longitude = Self.paris.longitude
        self.cityName = Self.paris.name
        self.hasLocation = false
        self.method = .franceMuslims12
        self.asrMadhab = .shafi
        self.fajrAdjustment = 0
        self.dhuhrAdjustment = 0
        self.asrAdjustment = 0
        self.maghribAdjustment = 0
        self.ishaAdjustment = 0
        self.notifyAtAdhan = true
        self.repeatUntilDone = true
        self.repeatInterval = .every15min
        self.quietMode = false
        self.activatedAt = activatedAt
    }

    var adjustments: [Prayer: Int] {
        get {
            [.fajr: fajrAdjustment, .dhuhr: dhuhrAdjustment, .asr: asrAdjustment, .maghrib: maghribAdjustment, .isha: ishaAdjustment]
        }
        set {
            fajrAdjustment = newValue[.fajr] ?? 0
            dhuhrAdjustment = newValue[.dhuhr] ?? 0
            asrAdjustment = newValue[.asr] ?? 0
            maghribAdjustment = newValue[.maghrib] ?? 0
            ishaAdjustment = newValue[.isha] ?? 0
        }
    }

    var calculator: PrayerTimesCalculator {
        PrayerTimesCalculator(latitude: latitude, longitude: longitude, method: method, madhab: asrMadhab, adjustments: adjustments)
    }

    /// "Paris · Musulmans de France 12°".
    var summary: String { "\(cityName) · \(method.label)" }
}

/// One prayer of one day. Created when ticked, or as missed once its day is over.
@Model
final class PrayerRecord {
    @Attribute(.unique) var id: UUID
    /// Start of the day (app calendar).
    var date: Date
    var prayer: Prayer
    var status: PrayerStatus
    var checkedAt: Date?

    init(date: Date, prayer: Prayer, status: PrayerStatus, checkedAt: Date? = nil) {
        self.id = UUID()
        self.date = date
        self.prayer = prayer
        self.status = status
        self.checkedAt = checkedAt
    }
}
