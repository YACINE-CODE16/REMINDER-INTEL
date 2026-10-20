import Foundation
import SwiftData

/// Something to do, optionally dated and filed in a space.
/// `isReminder` keeps the V1 behaviour (follow-up notifications until done); a plain task
/// gets a single notification at its due date, if it has one.
/// Named TaskItem because `Task` would shadow Swift concurrency's Task.
@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var dueDate: Date?
    var repeatInterval: RepeatInterval
    var status: ReminderStatus
    var createdAt: Date
    var remindersSent: Int
    /// What was dictated, kept for debugging the parser in DEBUG builds only.
    var rawTranscript: String?
    var note: String?
    var isReminder: Bool
    var space: Space?

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date?,
        repeatInterval: RepeatInterval = .none,
        status: ReminderStatus = .pending,
        createdAt: Date = .now,
        remindersSent: Int = 0,
        rawTranscript: String? = nil,
        note: String? = nil,
        isReminder: Bool = true,
        space: Space? = nil
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.repeatInterval = repeatInterval
        self.status = status
        self.createdAt = createdAt
        self.remindersSent = remindersSent
        self.rawTranscript = DictationPrivacy.kept(rawTranscript)
        self.note = note
        self.isReminder = isReminder
        self.space = space
    }

    func isOverdue(now: Date = .now) -> Bool {
        guard status == .pending, let dueDate else { return false }
        return dueDate < now
    }

    /// Pending first by due date, undated last.
    static func byDueDate(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (l?, r?): l < r
        case (_?, nil): true
        case (nil, _?): false
        case (nil, nil): lhs.createdAt < rhs.createdAt
        }
    }
}
