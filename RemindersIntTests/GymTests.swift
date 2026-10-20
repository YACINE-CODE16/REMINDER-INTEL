import Foundation
import Testing
@testable import RemindersInt

/// PR detection, Epley, progression curve.
struct GymMathTests {
    typealias Set = GymMath.SetValue

    @Test func epley() {
        #expect(abs(GymMath.epley(weight: 100, reps: 5) - 116.67) < 0.01)
        #expect(abs(GymMath.epley(weight: 80, reps: 8) - 101.33) < 0.01)
    }

    /// History: 80 × 8 and 85 × 5.
    private var history: GymMath.Records {
        var records = GymMath.Records()
        records.add(Set(reps: 8, weight: 80))
        records.add(Set(reps: 5, weight: 85))
        return records
    }

    @Test func heavierWeightIsPR() {
        #expect(GymMath.isPR(Set(reps: 2, weight: 87.5), kind: .weightReps, previous: history))
    }

    @Test func moreRepsAtSameWeightIsPR() {
        // 80 × 9 beats 80 × 8; its estimated 1RM (104) is also above 85 × 5 (99.2).
        #expect(GymMath.isPR(Set(reps: 9, weight: 80), kind: .weightReps, previous: history))
        // 85 × 6 beats 85 × 5 at the same weight.
        #expect(GymMath.isPR(Set(reps: 6, weight: 85), kind: .weightReps, previous: history))
    }

    @Test func lighterSetWithHigherEstimateIsPR() {
        // 70 × 15: estimated 1RM 105 > 101.3, at a weight never done before.
        #expect(GymMath.isPR(Set(reps: 15, weight: 70), kind: .weightReps, previous: history))
    }

    @Test func ordinarySetIsNotPR() {
        #expect(!GymMath.isPR(Set(reps: 8, weight: 80), kind: .weightReps, previous: history))
        #expect(!GymMath.isPR(Set(reps: 6, weight: 75), kind: .weightReps, previous: history))
    }

    @Test func firstSetsAreNotPRs() {
        let flags = GymMath.flagPRs([Set(reps: 8, weight: 60), Set(reps: 8, weight: 62.5), Set(reps: 8, weight: 62.5)], kind: .weightReps)
        #expect(flags == [false, true, false])
    }

    @Test func bodyweightAndCardio() {
        var records = GymMath.Records()
        records.add(Set(reps: 10, weight: nil))
        #expect(GymMath.isPR(Set(reps: 11, weight: nil), kind: .bodyweightReps, previous: records))
        var cardio = GymMath.Records()
        cardio.add(Set(reps: nil, weight: nil, meters: 5000))
        #expect(!GymMath.isPR(Set(reps: nil, weight: nil, meters: 4000), kind: .distance, previous: cardio))
    }

    /// Six bench sessions, 2.5 kg more every time: one point per session, rising.
    @Test func curveOnSixSessions() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let sessions = (0..<6).map { index -> (date: Date, sets: [Set]) in
            let weight = 75 + 2.5 * Double(index)
            return (start.addingTimeInterval(Double(index) * 3 * 86_400), [Set(reps: 8, weight: weight), Set(reps: 8, weight: weight), Set(reps: 7, weight: weight)])
        }
        let curve = GymMath.curve(sessions)
        #expect(curve.count == 6)
        #expect(curve.map(\.maxWeight) == [75, 77.5, 80, 82.5, 85, 87.5])
        #expect(zip(curve, curve.dropFirst()).allSatisfy { $0.best1RM < $1.best1RM })
        #expect(abs(curve[0].best1RM - GymMath.epley(weight: 75, reps: 8)) < 0.001)
    }

    @Test func streakAllowsTwoRestDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        func ago(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: today)! }
        // Trained 1, 3, 6, 8 days ago (gaps of 1 and 2 rest days), then a 4-day hole.
        let days: Swift.Set<Date> = [ago(1), ago(3), ago(6), ago(8), ago(13)]
        #expect(GymMath.streak(trainingDays: days, today: today, calendar: calendar) == 9)
        #expect(GymMath.streak(trainingDays: [ago(4)], today: today, calendar: calendar) == 0)
    }
}

/// Dictated gym sentences against the bundled exercise library.
struct GymVoiceTests {
    private static let context: GymContext = {
        struct Entry: Decodable {
            var id: String
            var fr: String
            var en: String
            var kind: ExerciseKind
            var aliases: [String]
        }
        let url = Bundle.main.url(forResource: "exercises", withExtension: "json")!
        let entries = try! JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
        let refs = entries.map { ExerciseRef(id: $0.id, nameFR: $0.fr, kind: $0.kind, names: [$0.fr, $0.en] + $0.aliases) }
        return GymContext(exercises: refs, templates: ["Push A", "Pull A", "Legs A"], isWorkoutActive: true)
    }()

    @Test func libraryHasSixtyExercises() {
        #expect(Self.context.exercises.count == 60)
    }

    struct SetCase: Sendable, CustomTestStringConvertible {
        var phrase: String
        var exercise: String
        var kind: ExerciseKind
        var expected: GymMath.SetValue
        var testDescription: String { phrase }
    }

    @Test(arguments: [
        SetCase(phrase: "Bench 85 kilos 5 reps", exercise: "bench_press", kind: .weightReps, expected: .init(reps: 5, weight: 85)),
        SetCase(phrase: "Développé couché 85 5", exercise: "bench_press", kind: .weightReps, expected: .init(reps: 5, weight: 85)),
        SetCase(phrase: "Squat 100 pour 3", exercise: "squat", kind: .weightReps, expected: .init(reps: 3, weight: 100)),
        SetCase(phrase: "Deadlift 140 kg 5 reps", exercise: "deadlift", kind: .weightReps, expected: .init(reps: 5, weight: 140)),
        SetCase(phrase: "Lateral raises 12 kilos 12", exercise: "lateral_raise", kind: .weightReps, expected: .init(reps: 12, weight: 12)),
        SetCase(phrase: "Pull ups 10", exercise: "pull_up", kind: .bodyweightReps, expected: .init(reps: 10, weight: nil)),
        SetCase(phrase: "Leg curl 40 pour 12", exercise: "leg_curl", kind: .weightReps, expected: .init(reps: 12, weight: 40)),
        SetCase(phrase: "DC 82,5 kg 6 reps", exercise: "bench_press", kind: .weightReps, expected: .init(reps: 6, weight: 82.5)),
    ])
    func sets(_ testCase: SetCase) {
        let parsed = FallbackParser(now: .now, gym: Self.context).parse(testCase.phrase).capture
        #expect(parsed.intent == .gymSet)
        #expect(parsed.gym?.exerciseID == testCase.exercise)
        #expect(parsed.gym?.set(for: testCase.kind) == testCase.expected)
    }

    @Test func commands() {
        func intent(_ phrase: String) -> CaptureIntent {
            FallbackParser(now: .now, gym: Self.context).parse(phrase).capture.intent
        }
        #expect(intent("Exercice suivant") == .gymNext)
        #expect(intent("Next exercise") == .gymNext)
        #expect(intent("Fin de séance") == .gymFinish)
        let start = FallbackParser(now: .now, gym: Self.context).parse("Je commence push A").capture
        #expect(start.intent == .gymStart)
        #expect(start.gym?.templateName == "Push A")
        // A set on the current exercise, without naming it.
        let current = FallbackParser(now: .now, gym: Self.context).parse("85 kilos 5 reps").capture
        #expect(current.intent == .gymSet)
        #expect(current.gym?.exerciseID == nil)
    }

    @Test(arguments: [
        "Rappelle-moi d'aller à la salle à 18h",
        "J'ai fait 2h de maths ce matin",
        "Il faut que je fasse les courses demain",
    ])
    func notGym(_ phrase: String) {
        #expect(!FallbackParser(now: .now, gym: Self.context).parse(phrase).capture.intent.isGym)
    }
}
