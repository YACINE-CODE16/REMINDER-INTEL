import Foundation

/// What the parser knows about the gym module when it reads a sentence.
nonisolated struct GymContext: Sendable {
    var exercises: [ExerciseRef]
    var templates: [String]
    var isWorkoutActive: Bool

    static let empty = GymContext(exercises: [], templates: [], isWorkoutActive: false)
    var isModuleOn: Bool { !exercises.isEmpty }
}

/// A dictated gym command: a set ("bench 85 kilos 5 reps"), next exercise, end, or start.
nonisolated struct GymCommand: Sendable, Equatable {
    var exerciseID: String?
    var templateName: String?
    var isFreeSession = false
    /// Numbers with an explicit unit.
    var weight: Double?
    var reps: Int?
    var seconds: Double?
    var meters: Double?
    /// "100 pour 3", "85 x 5": weight then reps.
    var pair: Pair?
    /// Numbers without unit, in order.
    var bare: [Double] = []

    struct Pair: Sendable, Equatable {
        var first: Double
        var second: Int
    }

    /// The set the numbers describe for an exercise of `kind`; nil when incomplete.
    func set(for kind: ExerciseKind) -> GymMath.SetValue? {
        switch kind {
        case .weightReps:
            var numbers = bare
            let weight = self.weight ?? pair?.first ?? (numbers.isEmpty ? nil : numbers.removeFirst())
            let reps = self.reps ?? pair?.second ?? (numbers.isEmpty ? nil : Int(numbers.removeFirst()))
            guard let weight, let reps, reps > 0 else { return nil }
            return GymMath.SetValue(reps: reps, weight: weight)
        case .bodyweightReps:
            let reps = self.reps ?? pair?.second ?? bare.first.map { Int($0) }
            guard let reps, reps > 0 else { return nil }
            return GymMath.SetValue(reps: reps, weight: weight)
        case .time:
            guard let seconds = seconds ?? bare.first, seconds > 0 else { return nil }
            return GymMath.SetValue(reps: nil, weight: nil, seconds: seconds)
        case .distance:
            guard let meters = meters ?? bare.first, meters > 0 else { return nil }
            return GymMath.SetValue(reps: nil, weight: nil, meters: meters)
        }
    }
}

/// Rule-based reading of gym sentences (FR and EN), used as is by the fallback parser and to
/// complete Foundation Models.
nonisolated enum GymParsing {
    private static let finishPattern = #"\bfin de (la )?seance\b|\bseance (finie|terminee)\b|\b(fini|termine) (la |ma )?seance\b|\bfinish (the )?workout\b|\bend (of )?workout\b"#
    private static let nextPattern = #"^\s*(exercice )?suivant\s*$|\bexercice suivant\b|\bprochain exercice\b|\bnext exercise\b|^\s*next\s*$"#
    private static let startPattern = #"\b(je commence|je demarre|on commence|on demarre|c est parti pour|je lance|lance|commencer|demarrer|start|starting)\b"#
    private static let reminderPattern = #"\brappelle moi\b|\bn oublie pas\b|\bfais moi penser\b"#

    static func command(in text: String, context: GymContext) -> (CaptureIntent, GymCommand)? {
        guard context.isModuleOn else { return nil }
        let normalized = SpaceRouter.normalize(text)
        guard !matches(normalized, reminderPattern) else { return nil }

        if matches(normalized, finishPattern) {
            return (.gymFinish, GymCommand())
        }
        if matches(normalized, nextPattern) {
            return (.gymNext, GymCommand())
        }
        if matches(normalized, startPattern) {
            let padded = " \(normalized) "
            if let template = context.templates.first(where: { padded.contains(" \(SpaceRouter.normalize($0)) ") }) {
                return (.gymStart, GymCommand(templateName: template))
            }
            if normalized.contains("seance libre") {
                return (.gymStart, GymCommand(isFreeSession: true))
            }
            if normalized.contains("seance") || normalized.contains("salle") || normalized.contains("workout") {
                return (.gymStart, GymCommand())
            }
        }

        var command = numbers(in: text)
        let exercise = matchExercise(in: text, exercises: context.exercises)
        command.exerciseID = exercise?.id
        let hasNumbers = command.weight != nil || command.reps != nil || command.seconds != nil || command.meters != nil || command.pair != nil || !command.bare.isEmpty
        let hasExplicitSet = command.weight != nil || command.reps != nil || command.pair != nil
        if (exercise != nil && hasNumbers) || (context.isWorkoutActive && hasExplicitSet) {
            return (.gymSet, command)
        }
        return nil
    }

    /// The exercise whose name or alias appears in the sentence, longest match first
    /// ("leg curl" before "curl", "développé couché haltères" before "développé couché").
    static func matchExercise(in text: String, exercises: [ExerciseRef]) -> ExerciseRef? {
        let padded = " \(SpaceRouter.normalize(text)) "
        var best: (ref: ExerciseRef, length: Int)?
        for exercise in exercises {
            for name in exercise.names {
                let key = SpaceRouter.normalize(name)
                guard !key.isEmpty, padded.contains(" \(key) ") else { continue }
                if key.count > (best?.length ?? 0) { best = (exercise, key.count) }
            }
        }
        return best?.ref
    }

    /// Weight, reps, time, distance, "X pour Y" and bare numbers.
    static func numbers(in text: String) -> GymCommand {
        var rest = text.lowercased()
        var command = GymCommand()
        func take(_ pattern: String) -> [String]? {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: rest, range: NSRange(rest.startIndex..., in: rest)),
                  let range = Range(match.range, in: rest)
            else { return nil }
            let groups = (0..<match.numberOfRanges).map { index -> String in
                Range(match.range(at: index), in: rest).map { String(rest[$0]) } ?? ""
            }
            rest.replaceSubrange(range, with: " ")
            return groups
        }
        func decimal(_ string: String) -> Double? {
            Double(string.replacingOccurrences(of: ",", with: "."))
        }
        let number = #"(\d+(?:[.,]\d+)?)"#
        if let match = take(number + #"\s*(?:kg|kgs|kilos?|kilogrammes?)\b"#) { command.weight = decimal(match[1]) }
        if let match = take(#"(\d+)\s*(?:reps?|r[ée]p[ée]titions?|r[ée]ps?|fois)\b"#) { command.reps = Int(match[1]) }
        if let match = take(number + #"\s*km\b"#), let km = decimal(match[1]) { command.meters = km * 1000 }
        if let match = take(#"(\d+)\s*(?:m|m[èe]tres?)\b"#), let meters = decimal(match[1]) { command.meters = meters }
        var seconds: Double = 0
        if let match = take(#"(\d+)\s*(?:min|minutes?)\b"#), let minutes = decimal(match[1]) { seconds += minutes * 60 }
        if let match = take(#"(\d+)\s*(?:s|sec|secondes?|seconds?)\b"#), let value = decimal(match[1]) { seconds += value }
        if seconds > 0 { command.seconds = seconds }
        if let match = take(number + #"\s*(?:pour|x|×|à|a|for)\s*(\d+)\b"#), let first = decimal(match[1]), let second = Int(match[2]) {
            command.pair = .init(first: first, second: second)
        }
        if let regex = try? NSRegularExpression(pattern: number) {
            command.bare = regex.matches(in: rest, range: NSRange(rest.startIndex..., in: rest)).compactMap { match in
                Range(match.range(at: 1), in: rest).flatMap { decimal(String(rest[$0])) }
            }
        }
        return command
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
