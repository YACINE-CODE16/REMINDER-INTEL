import Foundation

/// Gym calculations on plain values: estimated 1RM, records, PR flags, labels, curves,
/// weekly frequency and streak.
nonisolated enum GymMath {
    struct SetValue: Sendable, Equatable {
        var reps: Int?
        var weight: Double?
        var seconds: Double? = nil
        var meters: Double? = nil
    }

    /// Epley: weight × (1 + reps / 30).
    static func epley(weight: Double, reps: Int) -> Double {
        weight * (1 + Double(reps) / 30)
    }

    static func estimated1RM(_ set: SetValue) -> Double? {
        guard let weight = set.weight, weight > 0, let reps = set.reps, reps > 0 else { return nil }
        return epley(weight: weight, reps: reps)
    }

    /// Records of an exercise over a list of sets.
    struct Records: Sendable, Equatable {
        var maxWeight: Double?
        var best1RM: Double?
        /// Best reps at each weight.
        var maxRepsAtWeight: [Double: Int] = [:]
        var maxReps: Int?
        var maxSeconds: Double?
        var maxMeters: Double?
        /// Best total weight × reps of the exercise in one session.
        var maxSessionVolume: Double?

        var isEmpty: Bool {
            maxWeight == nil && maxReps == nil && maxSeconds == nil && maxMeters == nil
        }

        mutating func add(_ set: SetValue) {
            if let weight = set.weight, weight > 0 { maxWeight = max(maxWeight ?? 0, weight) }
            if let estimate = GymMath.estimated1RM(set) { best1RM = max(best1RM ?? 0, estimate) }
            if let reps = set.reps, reps > 0 {
                maxReps = max(maxReps ?? 0, reps)
                if let weight = set.weight, weight > 0 {
                    maxRepsAtWeight[weight] = max(maxRepsAtWeight[weight] ?? 0, reps)
                }
            }
            if let seconds = set.seconds, seconds > 0 { maxSeconds = max(maxSeconds ?? 0, seconds) }
            if let meters = set.meters, meters > 0 { maxMeters = max(maxMeters ?? 0, meters) }
        }
    }

    /// Records of sets grouped by session (for the session volume record).
    static func records(sessions: [[SetValue]]) -> Records {
        var records = Records()
        for sets in sessions {
            sets.forEach { records.add($0) }
            let volume = sets.reduce(0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) }
            if volume > 0 { records.maxSessionVolume = max(records.maxSessionVolume ?? 0, volume) }
        }
        return records
    }

    /// A set is a personal record when it beats everything done before it: heavier, higher
    /// estimated 1RM, or more reps at a weight already lifted (for weighted exercises); more
    /// reps, longer or farther otherwise. The very first sets of an exercise are not records.
    static func isPR(_ set: SetValue, kind: ExerciseKind, previous: Records) -> Bool {
        guard !previous.isEmpty else { return false }
        switch kind {
        case .weightReps:
            guard let weight = set.weight, weight > 0 else { return false }
            if weight > (previous.maxWeight ?? 0) { return true }
            if let estimate = estimated1RM(set), estimate > (previous.best1RM ?? 0) + 0.01 { return true }
            if let reps = set.reps, let best = previous.maxRepsAtWeight[weight], reps > best { return true }
            return false
        case .bodyweightReps:
            return (set.reps ?? 0) > (previous.maxReps ?? 0)
        case .time:
            return (set.seconds ?? 0) > (previous.maxSeconds ?? 0)
        case .distance:
            return (set.meters ?? 0) > (previous.maxMeters ?? 0)
        }
    }

    /// PR flags for chronological sets of one exercise.
    static func flagPRs(_ sets: [SetValue], kind: ExerciseKind) -> [Bool] {
        var records = Records()
        return sets.map { set in
            let flag = isPR(set, kind: kind, previous: records)
            records.add(set)
            return flag
        }
    }

    // MARK: - Labels

    /// "82,5", "80".
    static func kg(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "fr_FR")))
    }

    /// "80 × 8", "12 reps", "1:30", "2,5 km", "500 m".
    static func label(_ set: SetValue, kind: ExerciseKind) -> String {
        switch kind {
        case .weightReps:
            let weight = set.weight.map(kg) ?? "0"
            return "\(weight) × \(set.reps ?? 0)"
        case .bodyweightReps:
            if let weight = set.weight, weight > 0 { return "+\(kg(weight)) × \(set.reps ?? 0)" }
            return "\(set.reps ?? 0) reps"
        case .time:
            let seconds = Int(set.seconds ?? 0)
            return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
        case .distance:
            let meters = set.meters ?? 0
            return meters >= 1000 ? "\(kg((meters / 100).rounded() / 10)) km" : "\(Int(meters)) m"
        }
    }

    /// "80 kg × 8" (with the unit), for the "dernière fois" line and the toast.
    static func longLabel(_ set: SetValue, kind: ExerciseKind) -> String {
        guard kind == .weightReps else { return label(set, kind: kind) }
        return "\(set.weight.map(kg) ?? "0") kg × \(set.reps ?? 0)"
    }

    /// "4 × 30 kg" for done exercises (sets × heaviest), "3 × 12 reps" without weight.
    static func summary(_ sets: [SetValue], kind: ExerciseKind) -> String {
        guard !sets.isEmpty else { return "" }
        switch kind {
        case .weightReps:
            let heaviest = sets.compactMap(\.weight).max() ?? 0
            return "\(sets.count) × \(kg(heaviest)) kg"
        case .bodyweightReps:
            return "\(sets.count) × \(sets.compactMap(\.reps).max() ?? 0) reps"
        case .time, .distance:
            return sets.map { label($0, kind: kind) }.joined(separator: " · ")
        }
    }

    /// "6 240 kg".
    static func volumeLabel(_ volume: Double) -> String {
        "\(Int(volume.rounded()).formatted(.number.locale(Locale(identifier: "fr_FR")))) kg"
    }

    // MARK: - Curves

    struct CurvePoint: Sendable, Equatable, Identifiable {
        var date: Date
        var maxWeight: Double
        var best1RM: Double

        var id: Date { date }
    }

    /// One point per session that has weighted sets: heaviest weight and best estimated 1RM.
    static func curve(_ sessions: [(date: Date, sets: [SetValue])]) -> [CurvePoint] {
        sessions.compactMap { session in
            let weights = session.sets.compactMap(\.weight).filter { $0 > 0 }
            let estimates = session.sets.compactMap(estimated1RM)
            guard let maxWeight = weights.max(), let best = estimates.max() else { return nil }
            return CurvePoint(date: session.date, maxWeight: maxWeight, best1RM: best)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Frequency and streak

    /// Sessions per week over the last `weeks` weeks.
    static func weeklyFrequency(_ dates: [Date], now: Date, weeks: Int = 8) -> Double {
        let start = now.addingTimeInterval(-Double(weeks) * 7 * 86_400)
        let count = dates.filter { $0 >= start && $0 <= now }.count
        return Double(count) / Double(weeks)
    }

    /// Days since the start of the current training run, where a run allows up to
    /// `maxRestDays` rest days in a row; 0 once the last session is older than that.
    static func streak(trainingDays: Set<Date>, today: Date, calendar: Calendar, maxRestDays: Int = 2) -> Int {
        let days = trainingDays.map { calendar.startOfDay(for: $0) }.sorted(by: >)
        let start = calendar.startOfDay(for: today)
        guard let last = days.first,
              let gap = calendar.dateComponents([.day], from: last, to: start).day,
              gap <= maxRestDays
        else { return 0 }
        var first = last
        for day in days.dropFirst() {
            let rest = (calendar.dateComponents([.day], from: day, to: first).day ?? 0) - 1
            guard rest <= maxRestDays else { break }
            first = day
        }
        return (calendar.dateComponents([.day], from: first, to: start).day ?? 0) + 1
    }
}
