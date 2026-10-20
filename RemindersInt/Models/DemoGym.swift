#if DEBUG
import Foundation
import SwiftData

/// "Salle" space with the gym module, the 3 programmes, 20 weeks of Push / Pull / Legs with a
/// steady load progression, a 4-day break 11 days ago (so the run is recent), and two goals
/// (`-seedDemoGym YES`, once; `-resetDemoGym YES` first to redo it).
enum DemoGym {
    @MainActor
    static func reset(in context: ModelContext) {
        for space in (try? context.fetch(FetchDescriptor<Space>())) ?? [] where space.activeModule == .gym {
            context.delete(space)
        }
        for workout in (try? context.fetch(FetchDescriptor<Workout>())) ?? [] {
            context.delete(workout)
        }
        for template in (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? [] {
            context.delete(template)
        }
        try? context.save()
    }

    @MainActor
    static func insert(into context: ModelContext, now: Date = .now) {
        let spaces = (try? context.fetch(FetchDescriptor<Space>())) ?? []
        guard !spaces.contains(where: { $0.activeModule == .gym }) else { return }
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: now)

        let roots = spaces.filter { $0.parent == nil }
        let space = Space(name: "Salle", colorHex: "#34C759", sfSymbol: "dumbbell.fill", sortOrder: (roots.map(\.sortOrder).max() ?? -1) + 1)
        context.insert(space)
        GymService.shared.activate(on: space)
        let templates = GymService.shared.templates()
        guard templates.count == 3 else { return }

        // Training days: Mon / Wed / Fri, plus every other Saturday; nothing in a 4-day break
        // from 14 to 11 days ago; nothing today.
        var days: [Date] = []
        for daysAgo in (1...140).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let week = daysAgo / 7
            let trains = weekday == 2 || weekday == 4 || weekday == 6 || (weekday == 7 && week % 2 == 0)
            if trains, !(11...14).contains(daysAgo) { days.append(day) }
        }

        for (index, day) in days.enumerated() {
            let template = templates[index % 3]
            // Progress: one step every 3 sessions of the same programme.
            let level = Double(index / 3)
            let progress = level / Double(max(1, days.count / 3))
            let start = calendar.date(bySettingHour: 18, minute: 30, second: 0, of: day) ?? day
            var clock = start.addingTimeInterval(300)
            let session = Session(space: space, startedAt: start, endedAt: start, note: template.name)
            context.insert(session)
            let workout = Workout(session: session, template: template)
            context.insert(workout)
            workout.currentOrder = (template.sortedItems.last?.order ?? 0)
            for item in template.sortedItems {
                guard let exercise = item.exercise else { continue }
                let entry = WorkoutEntry(order: item.order, exercise: exercise, targetSets: item.targetSets, targetReps: item.targetReps, targetWeight: item.targetWeight, restSeconds: item.restSeconds)
                entry.workout = workout
                context.insert(entry)
                // From 85 % of the target 20 weeks ago to ~105 % now, in 2.5 kg steps.
                let weight = item.targetWeight.map { target in ((target * (0.85 + 0.2 * progress)) / 2.5).rounded() * 2.5 }
                for setIndex in 0..<item.targetSets {
                    // The last set of the day is one rep short now and then.
                    let reps = item.targetReps - (setIndex == item.targetSets - 1 && index % 4 == 1 ? 1 : 0)
                    let set = WorkoutSet(reps: reps, weightKg: weight, completedAt: clock)
                    set.entry = entry
                    context.insert(set)
                    clock = clock.addingTimeInterval(Double(item.restSeconds) + 45)
                }
            }
            session.endedAt = clock
            workout.summaryShownAt = clock
        }

        let exercises = GymService.shared.exercises()
        for exercise in exercises where !exercise.entries.isEmpty {
            GymService.shared.recomputePRs(of: exercise)
        }
        context.insert(Goal(space: space, title: "3 séances par semaine", kind: .count, target: 3, unit: "séances", period: .week, createdAt: today.addingTimeInterval(-140 * 86_400)))
        if let bench = exercises.first(where: { $0.id == "bench_press" }) {
            let goal = Goal(space: space, title: "Bench 100 kg", kind: .prWeight, target: 100, unit: "kg", period: .none, createdAt: today.addingTimeInterval(-60 * 86_400))
            goal.exerciseID = bench.id
            context.insert(goal)
        }
        try? context.save()
    }
}
#endif
