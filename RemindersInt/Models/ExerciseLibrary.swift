import Foundation
import SwiftData

/// The bundled bilingual exercise library (Resources/exercises.json) and the demo programmes.
enum ExerciseLibrary {
    private struct Entry: Decodable {
        var id: String
        var fr: String
        var en: String
        var muscle: MuscleGroup
        var kind: ExerciseKind
        var aliases: [String]
    }

    /// Adds the library exercises missing from the store (new ones after an update included).
    /// Names and aliases of library exercises follow the bundled file.
    @MainActor
    static func install(in context: ModelContext) {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return }
        let existing = Dictionary(((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for entry in entries {
            if let exercise = existing[entry.id] {
                exercise.nameFR = entry.fr
                exercise.nameEN = entry.en
                exercise.aliases = entry.aliases
            } else {
                context.insert(Exercise(id: entry.id, nameFR: entry.fr, nameEN: entry.en, aliases: entry.aliases, muscleGroup: entry.muscle, kind: entry.kind, isCustom: false))
            }
        }
    }

    /// Push A, Pull A, Legs A, when there is no programme yet.
    @MainActor
    static func installDemoTemplates(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<WorkoutTemplate>())) ?? 0
        guard count == 0 else { return }
        let exercises = Dictionary(((try? context.fetch(FetchDescriptor<Exercise>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // (exercise, sets, reps, weight, rest)
        let programmes: [(String, [(String, Int, Int, Double?, Int)])] = [
            ("Push A", [
                ("bench_press", 4, 8, 80, 120),
                ("incline_dumbbell_press", 3, 10, 26, 90),
                ("overhead_press", 3, 8, 45, 120),
                ("lateral_raise", 4, 12, 12, 60),
                ("triceps_pushdown", 3, 12, 30, 60),
            ]),
            ("Pull A", [
                ("deadlift", 3, 5, 140, 180),
                ("pull_up", 4, 8, nil, 120),
                ("barbell_row", 4, 8, 70, 90),
                ("face_pull", 3, 15, 20, 60),
                ("barbell_curl", 3, 10, 30, 60),
            ]),
            ("Legs A", [
                ("squat", 4, 6, 100, 180),
                ("romanian_deadlift", 3, 8, 90, 120),
                ("leg_press", 3, 12, 180, 90),
                ("leg_curl", 3, 12, 40, 60),
                ("calf_raise", 4, 15, 60, 60),
            ]),
        ]
        for (index, programme) in programmes.enumerated() {
            let template = WorkoutTemplate(name: programme.0, sortOrder: index)
            context.insert(template)
            for (order, item) in programme.1.enumerated() {
                guard let exercise = exercises[item.0] else { continue }
                let templateItem = TemplateItem(order: order, exercise: exercise, targetSets: item.1, targetReps: item.2, targetWeight: item.3, restSeconds: item.4)
                templateItem.template = template
                context.insert(templateItem)
            }
        }
        try? context.save()
    }
}
