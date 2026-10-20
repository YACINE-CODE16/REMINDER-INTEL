import Foundation
import Observation
import SwiftData
import UserNotifications

/// End-of-workout figures.
struct WorkoutSummary: Identifiable {
    let id = UUID()
    var name: String
    var duration: TimeInterval
    var volume: Double
    var setCount: Int
    /// "Développé couché 85 kg × 5", "Squat · volume 2 400 kg".
    var records: [String]
}

/// Gym module: workouts (a Session of the gym space plus its exercises and sets), PRs,
/// rest timer and its notification, and the gym part of the session Live Activity.
@MainActor
@Observable
final class GymService {
    static let shared = GymService()

    nonisolated static let restNotificationID = "gym-rest"
    static let defaultRest = 90

    /// Bumped on every change so views relying on relationships refresh.
    private(set) var revision = 0
    /// Bumped when the workout screen should open (voice start, Live Activity tap).
    private(set) var showWorkoutRequests = 0

    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    private var context: ModelContext? { container?.mainContext }

    func configure(with container: ModelContainer) {
        self.container = container
    }

    // MARK: - Module

    func gymSpace() -> Space? {
        let spaces = (try? context?.fetch(FetchDescriptor<Space>())) ?? []
        return spaces.filter { $0.activeModule == .gym && !$0.isArchived }.min { $0.createdAt < $1.createdAt }
    }

    func activate(on space: Space) {
        guard let context else { return }
        space.module = .gym
        try? context.save()
        ExerciseLibrary.installDemoTemplates(in: context)
        changed()
    }

    func deactivate(_ space: Space) {
        space.module = SpaceModule.none
        try? context?.save()
        changed()
    }

    func templates() -> [WorkoutTemplate] {
        ((try? context?.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    /// The programme done least recently (never done first).
    func suggestedTemplate() -> WorkoutTemplate? {
        templates().min { lhs, rhs in
            switch (lhs.lastDone, rhs.lastDone) {
            case (nil, nil): lhs.sortOrder < rhs.sortOrder
            case (nil, _): true
            case (_, nil): false
            case let (l?, r?): l < r
            }
        }
    }

    func exercises() -> [Exercise] {
        ((try? context?.fetch(FetchDescriptor<Exercise>())) ?? []).sorted { $0.nameFR < $1.nameFR }
    }

    // MARK: - Workout

    func activeWorkout() -> Workout? {
        guard let session = TrackingService.shared.activeSession() else { return nil }
        return session.workout
    }

    /// Starts a workout: a tracking session in the gym space (closing any other one) and
    /// the programme's exercises with their targets.
    @discardableResult
    func start(template: WorkoutTemplate?, transcript: String? = nil, at date: Date = .now) -> Workout? {
        guard let context, let space = gymSpace() else { return nil }
        if let current = activeWorkout() { return current }
        guard let session = TrackingService.shared.start(in: space, at: date, note: template?.name ?? "Séance libre", transcript: transcript) else { return nil }
        let workout = Workout(session: session, template: template)
        context.insert(workout)
        for item in template?.sortedItems ?? [] {
            guard let exercise = item.exercise else { continue }
            let entry = WorkoutEntry(order: item.order, exercise: exercise, targetSets: item.targetSets, targetReps: item.targetReps, targetWeight: item.targetWeight, restSeconds: item.restSeconds)
            entry.workout = workout
            context.insert(entry)
        }
        try? context.save()
        changed()
        return workout
    }

    /// Voice "Annuler" on a start: removes the session and its workout.
    func cancel(_ workout: Workout) {
        guard let session = workout.session else { return }
        clearRest(workout)
        TrackingService.shared.delete(session)
        changed()
    }

    /// Adds `exercise` to the workout (a free session, or off-programme) and makes it current.
    @discardableResult
    func add(_ exercise: Exercise, to workout: Workout) -> WorkoutEntry {
        if let existing = workout.entries.first(where: { $0.exercise?.id == exercise.id }) {
            workout.currentOrder = existing.order
            try? context?.save()
            changed()
            return existing
        }
        let entry = WorkoutEntry(order: (workout.entries.map(\.order).max() ?? -1) + 1, exercise: exercise, restSeconds: Self.defaultRest)
        entry.workout = workout
        context?.insert(entry)
        workout.currentOrder = entry.order
        try? context?.save()
        changed()
        return entry
    }

    /// Records a set on `exercise` (or the current one), flags PRs and starts the rest timer.
    @discardableResult
    func addSet(to exercise: Exercise? = nil, in workout: Workout, reps: Int?, weight: Double?, seconds: Double? = nil, meters: Double? = nil, at date: Date = .now) -> WorkoutSet? {
        guard let context else { return nil }
        let entry: WorkoutEntry
        if let exercise {
            entry = add(exercise, to: workout)
        } else if let current = workout.currentEntry {
            entry = current
        } else {
            return nil
        }
        let set = WorkoutSet(reps: reps, weightKg: weight, seconds: seconds, meters: meters, completedAt: date)
        set.entry = entry
        context.insert(set)
        workout.currentOrder = entry.order
        if let exercise = entry.exercise { recomputePRs(of: exercise) }
        startRest(workout, seconds: entry.restSeconds, after: entry, at: date)
        try? context.save()
        changed()
        return set
    }

    /// "+" on the card: the last set of the current exercise, or the last one ever done.
    @discardableResult
    func copyLastSet(in workout: Workout) -> WorkoutSet? {
        guard let entry = workout.currentEntry, let exercise = entry.exercise else { return nil }
        let source = entry.sortedSets.last ?? lastSet(of: exercise, before: workout)
        if let source {
            return addSet(in: workout, reps: source.reps, weight: source.weightKg, seconds: source.seconds, meters: source.meters)
        }
        // First set ever: the programme target.
        return addSet(in: workout, reps: entry.targetReps ?? 10, weight: entry.targetWeight)
    }

    func update(_ set: WorkoutSet, reps: Int?, weight: Double?, seconds: Double? = nil, meters: Double? = nil) {
        set.reps = reps
        set.weightKg = weight
        set.seconds = seconds
        set.meters = meters
        if let exercise = set.entry?.exercise { recomputePRs(of: exercise) }
        try? context?.save()
        changed()
    }

    func delete(_ set: WorkoutSet) {
        let exercise = set.entry?.exercise
        let workout = set.entry?.workout
        context?.delete(set)
        if let exercise { recomputePRs(of: exercise) }
        if let workout, workout.entries.flatMap(\.sets).isEmpty { clearRest(workout) }
        try? context?.save()
        changed()
    }

    /// Next exercise of the programme (or the next one added).
    @discardableResult
    func next(in workout: Workout) -> WorkoutEntry? {
        let entries = workout.sortedEntries
        guard let index = entries.firstIndex(where: { $0.order == workout.currentOrder }), index + 1 < entries.count else { return nil }
        workout.currentOrder = entries[index + 1].order
        clearRest(workout)
        try? context?.save()
        changed()
        return entries[index + 1]
    }

    /// Voice "Annuler" on "exercice suivant".
    func previous(in workout: Workout) {
        let entries = workout.sortedEntries
        guard let index = entries.firstIndex(where: { $0.order == workout.currentOrder }), index > 0 else { return }
        workout.currentOrder = entries[index - 1].order
        try? context?.save()
        changed()
    }

    /// Ends the workout: closes its session and returns the summary.
    @discardableResult
    func finish(_ workout: Workout, at date: Date = .now) -> WorkoutSummary {
        clearRest(workout)
        workout.summaryShownAt = date
        let summary = self.summary(of: workout, now: date)
        if workout.isActive {
            TrackingService.shared.stop(at: date)
        }
        changed()
        return summary
    }

    /// Voice "Annuler" on "fin de séance": the session is open again.
    func reopen(_ workout: Workout) {
        guard let session = workout.session, !session.isActive else { return }
        session.endedAt = nil
        workout.summaryShownAt = nil
        try? context?.save()
        TrackingService.shared.resume()
        changed()
    }

    /// Summary of a workout ended outside the app in the last 12 hours, given once.
    func takePendingSummary(now: Date = .now) -> WorkoutSummary? {
        let recent = now.addingTimeInterval(-12 * 3600)
        let ended = ((try? context?.fetch(FetchDescriptor<Workout>())) ?? []).filter { workout in
            guard workout.summaryShownAt == nil, let session = workout.session, let end = session.endedAt else { return false }
            return end >= recent
        }
        guard let latest = ended.max(by: { $0.startedAt < $1.startedAt }) else { return nil }
        ended.forEach { $0.summaryShownAt = now }
        try? context?.save()
        return summary(of: latest, now: now)
    }

    func summary(of workout: Workout, now: Date = .now) -> WorkoutSummary {
        var records: [String] = []
        for entry in workout.sortedEntries {
            guard let exercise = entry.exercise else { continue }
            for set in entry.sortedSets where set.isPR {
                records.append("\(exercise.nameFR) \(GymMath.longLabel(set.value, kind: exercise.kind))")
            }
            // Session volume record on the exercise.
            let volume = entry.sets.reduce(0) { $0 + $1.volume }
            let earlier = exercise.entries.filter { $0.workout?.id != workout.id && ($0.workout?.startedAt ?? .distantFuture) < workout.startedAt }
            let best = earlier.map { $0.sets.reduce(0) { $0 + $1.volume } }.max()
            if volume > 0, let best, volume > best {
                records.append("\(exercise.nameFR) · volume \(GymMath.volumeLabel(volume))")
            }
        }
        return WorkoutSummary(
            name: workout.name,
            duration: workout.session?.duration(now: now) ?? 0,
            volume: workout.volume,
            setCount: workout.entries.flatMap(\.sets).count,
            records: records
        )
    }

    // MARK: - Records

    /// Re-flags every set of the exercise in chronological order.
    func recomputePRs(of exercise: Exercise) {
        let sets = exercise.allSets
        let flags = GymMath.flagPRs(sets.map(\.value), kind: exercise.kind)
        for (set, flag) in zip(sets, flags) where set.isPR != flag {
            set.isPR = flag
        }
    }

    func lastSet(of exercise: Exercise, before workout: Workout? = nil) -> WorkoutSet? {
        exercise.allSets.last { set in
            guard let workout else { return true }
            return set.entry?.workout?.id != workout.id
        }
    }

    func records(of exercise: Exercise) -> GymMath.Records {
        let sessions = exercise.entries.map { $0.sets.map(\.value) }
        return GymMath.records(sessions: sessions)
    }

    /// One point per workout: heaviest weight and best estimated 1RM.
    func curve(of exercise: Exercise, since start: Date) -> [GymMath.CurvePoint] {
        let sessions = exercise.entries.compactMap { entry -> (date: Date, sets: [GymMath.SetValue])? in
            guard let date = entry.workout?.startedAt, date >= start else { return nil }
            return (date, entry.sets.map(\.value))
        }
        return GymMath.curve(sessions)
    }

    // MARK: - Rest timer

    private func startRest(_ workout: Workout, seconds: Int, after entry: WorkoutEntry, at date: Date) {
        let end = date.addingTimeInterval(TimeInterval(seconds))
        workout.restEndsAt = end
        center.removePendingNotificationRequests(withIdentifiers: [Self.restNotificationID])
        let content = UNMutableNotificationContent()
        content.title = "Repos terminé"
        let setNumber = entry.sets.count + 1
        content.body = "S\(setNumber) · \(entry.exercise?.nameFR ?? "Exercice suivant")"
        content.sound = .default
        content.threadIdentifier = "gym"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, end.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.restNotificationID, content: content, trigger: trigger))
    }

    private func clearRest(_ workout: Workout) {
        workout.restEndsAt = nil
        center.removePendingNotificationRequests(withIdentifiers: [Self.restNotificationID])
    }

    // MARK: - Live Activity

    /// Gym line of the session Live Activity: current exercise, last set, rest end.
    func activityInfo(for session: Session) -> (exercise: String?, lastSet: String?, restEndsAt: Date?) {
        guard let workout = session.workout, let entry = workout.currentEntry, let exercise = entry.exercise else { return (nil, nil, nil) }
        let last = entry.sortedSets.last.map { GymMath.label($0.value, kind: exercise.kind) }
        return (exercise.nameFR, last, workout.restEndsAt)
    }

    func requestWorkoutScreen() {
        showWorkoutRequests += 1
    }

    private func changed() {
        revision += 1
        TrackingService.shared.refreshActivity()
    }
}
