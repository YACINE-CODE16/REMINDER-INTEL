import Foundation
import SwiftData

nonisolated enum RepeatInterval: String, Codable, CaseIterable, Identifiable {
    case none
    case every5min
    case every15min
    case every30min
    case hourly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "Aucune relance"
        case .every5min: "Toutes les 5 min"
        case .every15min: "Toutes les 15 min"
        case .every30min: "Toutes les 30 min"
        case .hourly: "Toutes les heures"
        }
    }
}

nonisolated enum ReminderStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case done
    case cancelled

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: "En attente"
        case .done: "Fait"
        case .cancelled: "Annulé"
        }
    }
}

@Model
final class Reminder {
    @Attribute(.unique) var id: UUID
    var title: String
    var dueDate: Date
    var repeatInterval: RepeatInterval
    var status: ReminderStatus
    var createdAt: Date
    var remindersSent: Int
    /// What was dictated, kept for debugging the parser.
    var rawTranscript: String?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date,
        repeatInterval: RepeatInterval = .none,
        status: ReminderStatus = .pending,
        createdAt: Date = .now,
        remindersSent: Int = 0,
        rawTranscript: String? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.repeatInterval = repeatInterval
        self.status = status
        self.createdAt = createdAt
        self.remindersSent = remindersSent
        self.rawTranscript = rawTranscript
    }
}
