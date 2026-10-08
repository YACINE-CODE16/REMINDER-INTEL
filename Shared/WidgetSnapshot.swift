import Foundation

/// Upcoming pending reminders, written by the app into the App Group for the widget.
/// Keeps the widget free of SwiftData and of the app's store location.
nonisolated struct WidgetSnapshot: Codable, Sendable {
    struct Item: Codable, Sendable, Identifiable {
        var id: UUID
        var title: String
        var dueDate: Date
    }

    var upcoming: [Item]

    private static let storageKey = "widgetSnapshot"

    static func load() -> WidgetSnapshot? {
        guard let data = AppGroup.defaults?.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        AppGroup.defaults?.set(data, forKey: Self.storageKey)
    }
}
