import Foundation

extension Locale {
    static let app = Locale(identifier: "fr_FR")
}

extension Calendar {
    /// Gregorian calendar, French locale, weeks starting on Monday.
    static let app: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .app
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }()

    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? startOfDay(for: date)
    }
}

enum AppStorageKey {
    static let defaultRepeatInterval = "defaultRepeatInterval"
    static let hasSeededDemoData = "hasSeededDemoData"
}
