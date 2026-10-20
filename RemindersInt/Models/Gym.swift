import Foundation
import SwiftData

nonisolated enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case legs
    case glutes
    case core
    case cardio
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: "Pectoraux"
        case .back: "Dos"
        case .shoulders: "Épaules"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .legs: "Jambes"
        case .glutes: "Fessiers"
        case .core: "Abdos"
        case .cardio: "Cardio"
        case .other: "Autre"
        }
    }
}

nonisolated enum ExerciseKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case weightReps
    case bodyweightReps
    case time
    case distance

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weightReps: "Charge × reps"
        case .bodyweightReps: "Poids du corps"
        case .time: "Durée"
        case .distance: "Distance"
        }
    }
}

/// An exercise of the library (bundled, bilingual, with dictation aliases) or created by the user.
@Model
final class Exercise {
    /// Library slug ("bench_press") or "custom-<uuid>".
    @Attribute(.unique) var id: String
    var nameFR: String
    var nameEN: String
    var aliases: [String]
    var muscleGroup: MuscleGroup
    var kind: ExerciseKind
    var isCustom: Bool
    @Relationship(deleteRule: .nullify, inverse: \WorkoutEntry.exercise) var entries: [WorkoutEntry] = []
    @Relationship(deleteRule: .nullify, inverse: \TemplateItem.exercise) var templateItems: [TemplateItem] = []

    init(id: String, nameFR: String, nameEN: String, aliases: [String], muscleGroup: MuscleGroup, kind: ExerciseKind, isCustom: Bool) {
        self.id = id
        self.nameFR = nameFR
        self.nameEN = nameEN
        self.aliases = aliases
        self.muscleGroup = muscleGroup
        self.kind = kind
        self.isCustom = isCustom
    }

    var ref: ExerciseRef {
        ExerciseRef(id: id, nameFR: nameFR, kind: kind, names: [nameFR, nameEN] + aliases)
    }

    /// Every set ever done, oldest first.
    var allSets: [WorkoutSet] {
        entries.flatMap(\.sets).sorted { $0.completedAt < $1.completedAt }
    }

    /// Best weight ever lifted (the PR fed to prWeight goals).
    var maxWeight: Double? {
        allSets.compactMap(\.weightKg).max()
    }
}

/// Plain copy of an exercise for the parser, which runs outside SwiftData.
nonisolated struct ExerciseRef: Sendable, Equatable {
    var id: String
    var nameFR: String
    var kind: ExerciseKind
    /// FR / EN names and aliases.
    var names: [String]
}

/// A programme: ordered exercises with their targets.
@Model
final class WorkoutTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int
    @Relationship(deleteRule: .cascade, inverse: \TemplateItem.template) var items: [TemplateItem] = []
    @Relationship(deleteRule: .nullify, inverse: \Workout.template) var workouts: [Workout] = []

    init(name: String, sortOrder: Int) {
        self.id = UUID()
        self.name = name
        self.sortOrder = sortOrder
    }

    var sortedItems: [TemplateItem] { items.sorted { $0.order < $1.order } }

    /// Last time it was done, for "prochain programme suggéré".
    var lastDone: Date? {
        workouts.compactMap { $0.session?.startedAt }.max()
    }
}

@Model
final class TemplateItem {
    @Attribute(.unique) var id: UUID
    var order: Int
    var exercise: Exercise?
    var template: WorkoutTemplate?
    var targetSets: Int
    var targetReps: Int
    var targetWeight: Double?
    var restSeconds: Int

    init(order: Int, exercise: Exercise, targetSets: Int, targetReps: Int, targetWeight: Double?, restSeconds: Int) {
        self.id = UUID()
        self.order = order
        self.exercise = exercise
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.restSeconds = restSeconds
    }
}

/// A gym session: the time is a Session of the gym space (step 6b), the content is here.
@Model
final class Workout {
    @Attribute(.unique) var id: UUID
    var session: Session?
    var template: WorkoutTemplate?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutEntry.workout) var entries: [WorkoutEntry] = []
    /// Order of the exercise being done.
    var currentOrder: Int
    /// End of the running rest timer.
    var restEndsAt: Date?

    init(session: Session, template: WorkoutTemplate?) {
        self.id = UUID()
        self.session = session
        self.template = template
        self.currentOrder = 0
    }

    var isActive: Bool { session?.isActive ?? false }
    var startedAt: Date { session?.startedAt ?? .distantPast }
    var sortedEntries: [WorkoutEntry] { entries.sorted { $0.order < $1.order } }
    var currentEntry: WorkoutEntry? { sortedEntries.first { $0.order == currentOrder } ?? sortedEntries.last }
    var name: String { template?.name ?? "Séance libre" }

    /// Sum of weight × reps.
    var volume: Double {
        entries.flatMap(\.sets).reduce(0) { $0 + $1.volume }
    }

    var prCount: Int { entries.flatMap(\.sets).filter(\.isPR).count }
}

@Model
final class WorkoutEntry {
    @Attribute(.unique) var id: UUID
    var order: Int
    var exercise: Exercise?
    var workout: Workout?
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.entry) var sets: [WorkoutSet] = []
    /// Copied from the programme, for "4 × 12 · 12 kg".
    var targetSets: Int?
    var targetReps: Int?
    var targetWeight: Double?
    var restSeconds: Int

    init(order: Int, exercise: Exercise, targetSets: Int? = nil, targetReps: Int? = nil, targetWeight: Double? = nil, restSeconds: Int = 90) {
        self.id = UUID()
        self.order = order
        self.exercise = exercise
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.restSeconds = restSeconds
    }

    var sortedSets: [WorkoutSet] { sets.sorted { $0.completedAt < $1.completedAt } }
}

@Model
final class WorkoutSet {
    @Attribute(.unique) var id: UUID
    var reps: Int?
    var weightKg: Double?
    var seconds: Double?
    var meters: Double?
    var isPR: Bool
    var completedAt: Date
    var entry: WorkoutEntry?

    init(reps: Int?, weightKg: Double?, seconds: Double? = nil, meters: Double? = nil, completedAt: Date = .now) {
        self.id = UUID()
        self.reps = reps
        self.weightKg = weightKg
        self.seconds = seconds
        self.meters = meters
        self.isPR = false
        self.completedAt = completedAt
    }

    var volume: Double { (weightKg ?? 0) * Double(reps ?? 0) }

    var value: GymMath.SetValue {
        GymMath.SetValue(reps: reps, weight: weightKg, seconds: seconds, meters: meters)
    }
}
