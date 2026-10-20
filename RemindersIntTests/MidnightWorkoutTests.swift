import Foundation
import SwiftData
import Testing
@testable import RemindersInt

/// Step 8b: a gym workout from 23:30 to 00:45.
@MainActor
struct MidnightWorkoutTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()

    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 23, minute: 30))! }
    private var end: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 0, minute: 45))! }

    @Test func plainSessionIsSplitAtMidnight() {
        let pieces = SessionSplit.closing(from: start, to: end, hasWorkout: false, calendar: calendar)
        #expect(pieces.count == 2)
        #expect(pieces.map { $0.end.timeIntervalSince($0.start) / 60 } == [30, 45])
    }

    @Test func workoutKeepsItsSessionWhole() {
        let pieces = SessionSplit.closing(from: start, to: end, hasWorkout: true, calendar: calendar)
        #expect(pieces.count == 1)
        #expect(pieces[0].start == start && pieces[0].end == end)
    }

    /// One session with its workout: 1 h 15 and the whole volume on it, 30 / 45 min per day.
    @Test func totalsAndWorkoutAcrossMidnight() throws {
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV1.self), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let space = Space(name: "Salle", colorHex: "#34C759", sfSymbol: "dumbbell.fill")
        context.insert(space)
        let session = Session(space: space, startedAt: start, endedAt: end)
        context.insert(session)
        let workout = Workout(session: session, template: nil)
        context.insert(workout)
        let squat = Exercise(id: "squat", nameFR: "Squat", nameEN: "Back squat", aliases: [], muscleGroup: .legs, kind: .weightReps, isCustom: false)
        context.insert(squat)
        let entry = WorkoutEntry(order: 0, exercise: squat)
        entry.workout = workout
        context.insert(entry)
        // Two sets before midnight, two after.
        for (minutes, weight) in [(10.0, 100.0), (25, 100), (40, 105), (70, 105)] {
            let set = WorkoutSet(reps: 5, weightKg: weight, completedAt: start.addingTimeInterval(minutes * 60))
            set.entry = entry
            context.insert(set)
        }
        try context.save()

        #expect(session.duration(now: end) == 75 * 60)
        #expect(workout.volume == 5 * (100 + 100 + 105 + 105))
        #expect(workout.session?.id == session.id)
        let firstDay = TimeTotals.day(containing: start, calendar: calendar)
        let secondDay = TimeTotals.day(containing: end, calendar: calendar)
        #expect(TimeTotals.seconds([session], in: firstDay, now: end) == 30 * 60)
        #expect(TimeTotals.seconds([session], in: secondDay, now: end) == 45 * 60)
    }
}
