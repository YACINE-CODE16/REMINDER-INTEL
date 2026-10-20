import Foundation
import SwiftData
import Testing
@testable import RemindersInt

/// Step 8a: data safety.
@MainActor
struct DataSafetyTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TaskItem.self, Space.self, Session.self, Goal.self, GoalStep.self, PrayerSettings.self, PrayerRecord.self,
            Exercise.self, WorkoutTemplate.self, TemplateItem.self, Workout.self, WorkoutEntry.self, WorkoutSet.self, Reminder.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Deleting a session deletes its workout (cascade); recomputing then ignores its sets.
    @Test func prsAreRecomputedWithoutDeletedWorkout() throws {
        let context = try makeContext()
        let space = Space(name: "Salle", colorHex: "#34C759", sfSymbol: "dumbbell.fill")
        context.insert(space)
        let bench = Exercise(id: "bench_press", nameFR: "Développé couché", nameEN: "Bench press", aliases: [], muscleGroup: .chest, kind: .weightReps, isCustom: false)
        context.insert(bench)

        var sessions: [Session] = []
        for (index, weight) in [80.0, 85, 90].enumerated() {
            let start = Date(timeIntervalSince1970: 1_790_000_000 + Double(index) * 86_400)
            let session = Session(space: space, startedAt: start, endedAt: start.addingTimeInterval(3600))
            context.insert(session)
            let workout = Workout(session: session, template: nil)
            context.insert(workout)
            let entry = WorkoutEntry(order: 0, exercise: bench)
            entry.workout = workout
            context.insert(entry)
            let set = WorkoutSet(reps: 5, weightKg: weight, completedAt: start.addingTimeInterval(600))
            set.entry = entry
            context.insert(set)
            sessions.append(session)
        }
        try context.save()
        GymService.shared.recomputePRs(of: bench)
        #expect(bench.allSets.map(\.isPR) == [false, true, true])

        // The first workout goes: 85 becomes the first set ever, no longer a record.
        context.delete(sessions[0])
        try context.save()
        GymService.shared.recomputePRs(of: bench)
        #expect(bench.allSets.map(\.weightKg) == [85, 90])
        #expect(bench.allSets.map(\.isPR) == [false, true])
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 2)
    }

    @Test func deletionMessageMentionsTheWorkout() throws {
        let context = try makeContext()
        let space = Space(name: "Salle", colorHex: "#34C759", sfSymbol: "dumbbell.fill")
        context.insert(space)
        let session = Session(space: space, startedAt: .now.addingTimeInterval(-3600), endedAt: .now)
        context.insert(session)
        #expect(TrackingView.deletionMessage(for: session).contains("session"))
        let workout = Workout(session: session, template: nil)
        context.insert(workout)
        let exercise = Exercise(id: "squat", nameFR: "Squat", nameEN: "Back squat", aliases: [], muscleGroup: .legs, kind: .weightReps, isCustom: false)
        context.insert(exercise)
        let entry = WorkoutEntry(order: 0, exercise: exercise)
        entry.workout = workout
        context.insert(entry)
        let set = WorkoutSet(reps: 5, weightKg: 100)
        set.entry = entry
        context.insert(set)
        try context.save()
        let message = TrackingView.deletionMessage(for: session)
        #expect(message.contains("séance de muscu"))
        #expect(message.contains("1 série"))
    }
}
