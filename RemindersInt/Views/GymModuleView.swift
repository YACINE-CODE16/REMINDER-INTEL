import SwiftUI
import SwiftData

/// Gym module block at the top of the space detail: the running workout (mockup 12), or the
/// suggested programme, the training grid and the last workouts.
struct GymModuleView: View {
    let space: Space

    @Query private var sessions: [Session]
    @Query(sort: \WorkoutTemplate.sortOrder) private var templates: [WorkoutTemplate]
    @State private var editedSet: WorkoutSet?
    @State private var isPickingExercise = false
    @State private var isConfirmingFinish = false
    @State private var summary: WorkoutSummary?
    @State private var shownExercise: Exercise?
    @State private var isShowingLibrary = false
    private let service = GymService.shared

    var body: some View {
        let _ = service.revision
        VStack(spacing: 14) {
            if let workout = service.activeWorkout() {
                workoutSection(workout)
            } else {
                overview
            }
            trainingCard
        }
        .sheet(item: $editedSet) { set in
            SetEditSheet(set: set)
        }
        .sheet(isPresented: $isPickingExercise) {
            ExercisePickerSheet { exercise in
                if let workout = service.activeWorkout() {
                    withAnimation(.appSpring) { _ = service.add(exercise, to: workout) }
                }
            }
        }
        .sheet(item: $summary) { summary in
            WorkoutSummaryView(summary: summary)
        }
        .sheet(item: $shownExercise) { exercise in
            NavigationStack { ExerciseDetailView(exercise: exercise) }
        }
        .sheet(isPresented: $isShowingLibrary) {
            NavigationStack { ExerciseLibraryView() }
        }
    }

    // MARK: - Running workout

    @ViewBuilder
    private func workoutSection(_ workout: Workout) -> some View {
        if let entry = workout.currentEntry, let exercise = entry.exercise {
            CurrentExerciseCard(
                workout: workout,
                entry: entry,
                exercise: exercise,
                onEditSet: { editedSet = $0 },
                onShowExercise: { shownExercise = exercise }
            )
        } else {
            GlassCard {
                Text("Ajoute un premier exercice pour commencer.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondary)
            }
        }

        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    withAnimation(.appSpring) { _ = service.next(in: workout) }
                } label: {
                    Label("Exercice suivant", systemImage: "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(.white.opacity(0.55)).interactive(), in: .capsule)
                .disabled(workout.sortedEntries.last?.order == workout.currentOrder)

                Button("Terminer") { isConfirmingFinish = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 112, height: 46)
                    .background(Palette.red, in: .capsule)
                    .buttonStyle(.plain)
            }
        }
        .confirmationDialog("Terminer la séance ?", isPresented: $isConfirmingFinish, titleVisibility: .visible) {
            Button("Terminer") {
                withAnimation(.appSpring) { summary = service.finish(workout) }
            }
            Button("Continuer", role: .cancel) {}
        }

        sessionCard(workout)
    }

    private func sessionCard(_ workout: Workout) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Séance")
                        .font(.title3.bold())
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Text("volume \(GymMath.volumeLabel(workout.volume))")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.secondary)
                }
                ForEach(workout.sortedEntries) { entry in
                    WorkoutEntryRow(entry: entry, isCurrent: entry.order == workout.currentOrder)
                        .contentShape(.rect)
                        .onTapGesture {
                            withAnimation(.appSpring) {
                                workout.currentOrder = entry.order
                                try? workout.modelContext?.save()
                                TrackingService.shared.refreshActivity()
                            }
                        }
                        .contextMenu {
                            if let last = entry.sortedSets.last {
                                Button("Supprimer la dernière série", systemImage: "trash", role: .destructive) {
                                    withAnimation(.appSpring) { service.delete(last) }
                                }
                            }
                            if let exercise = entry.exercise {
                                Button("Historique", systemImage: "chart.xyaxis.line") { shownExercise = exercise }
                            }
                        }
                }
                Button {
                    isPickingExercise = true
                } label: {
                    Label("Ajouter un exercice", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.blue)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Overview

    private var overview: some View {
        let suggested = service.suggestedTemplate()
        return VStack(spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("PROCHAIN PROGRAMME")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                    if let suggested {
                        HStack(alignment: .firstTextBaseline) {
                            Text(suggested.name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Text(suggested.lastDone.map { "fait \(Self.relativeDay($0))" } ?? "jamais fait")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.secondary)
                        }
                        Text(suggested.sortedItems.compactMap { $0.exercise?.nameFR }.joined(separator: " · "))
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.secondary)
                            .lineLimit(2)
                    }
                    Button {
                        withAnimation(.appSpring) { _ = service.start(template: suggested) }
                    } label: {
                        Label("Démarrer", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Palette.green, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(templates.filter { $0.id != suggested?.id }) { template in
                                chip(template.name) { _ = service.start(template: template) }
                            }
                            chip("Séance libre") { _ = service.start(template: nil) }
                            chip("Exercices") { isShowingLibrary = true }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            lastWorkoutsCard
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.appSpring) { action() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Palette.text.opacity(0.06), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var workouts: [Workout] {
        sessions.filter { $0.space.map(space.contains) ?? false }.compactMap(\.workout)
            .sorted { $0.startedAt > $1.startedAt }
    }

    @ViewBuilder
    private var lastWorkoutsCard: some View {
        let recent = workouts.filter { !$0.isActive }.prefix(5)
        if !recent.isEmpty {
            GlassCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Dernières séances")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    ForEach(Array(recent)) { workout in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(workout.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Palette.text)
                                Text("\(Self.relativeDay(workout.startedAt)) · \(TimeFormat.short(workout.session?.duration() ?? 0))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            if workout.prCount > 0 {
                                Text("\(workout.prCount) PR")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Palette.green)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(Palette.green.opacity(0.15), in: .capsule)
                            }
                            Text(GymMath.volumeLabel(workout.volume))
                                .font(.system(size: 13, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.text)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Training grid

    private var trainingCard: some View {
        let now = Date.now
        let calendar = Calendar.app
        let all = workouts
        var volumeByDay: [Date: Double] = [:]
        for workout in all {
            volumeByDay[calendar.startOfDay(for: workout.startedAt), default: 0] += max(workout.volume, 1)
        }
        let maximum = volumeByDay.values.max() ?? 1
        // A training day is never lighter than the second step, whatever its volume.
        let values = volumeByDay.mapValues { max(0.2, $0 / maximum) }
        let frequency = GymMath.weeklyFrequency(all.map(\.startedAt), now: now)
        let streak = GymMath.streak(trainingDays: Set(volumeByDay.keys), today: now, calendar: calendar)
        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Entraînements")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Spacer(minLength: 8)
                    Text("\(frequency.formatted(.number.precision(.fractionLength(1)).locale(.app))) / sem. · série \(streak) j")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(space.color)
                }
                ContributionGrid(values: values, color: space.color, weeks: 20, today: now)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// "aujourd'hui", "hier", "lun. 12 oct.".
    static func relativeDay(_ date: Date) -> String {
        let calendar = Calendar.app
        if calendar.isDateInToday(date) { return "aujourd'hui" }
        if calendar.isDateInYesterday(date) { return "hier" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(.app))
    }
}

/// Black card of the current exercise: name, last time, sets as pills, + and rest bar.
struct CurrentExerciseCard: View {
    let workout: Workout
    let entry: WorkoutEntry
    let exercise: Exercise
    var onEditSet: (WorkoutSet) -> Void
    var onShowExercise: () -> Void

    private let service = GymService.shared

    private var lastTime: String? {
        service.lastSet(of: exercise, before: workout).map { "dernière fois \(GymMath.longLabel($0.value, kind: exercise.kind))" }
    }

    var body: some View {
        let index = (workout.sortedEntries.firstIndex { $0.id == entry.id } ?? 0) + 1
        let sets = entry.sortedSets
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: onShowExercise) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EXERCICE \(index)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(exercise.nameFR)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text([exercise.nameEN, lastTime].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if sets.contains(where: \.isPR) {
                    Text("PR")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Palette.green, in: .capsule)
                }
            }

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(sets.enumerated()), id: \.element.id) { offset, set in
                        Button { onEditSet(set) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("S\(offset + 1)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.6))
                                Text(GymMath.label(set.value, kind: exercise.kind))
                                    .font(.system(size: 15, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(set.isPR ? Palette.green.opacity(0.28) : .white.opacity(0.12), in: .rect(cornerRadius: 14))
                            .overlay {
                                if set.isPR {
                                    RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.green, lineWidth: 1.5)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                withAnimation(.appSpring) { service.delete(set) }
                            }
                        }
                        .accessibilityLabel("Série \(offset + 1), \(GymMath.longLabel(set.value, kind: exercise.kind))\(set.isPR ? ", record" : "")")
                    }
                    Button {
                        withAnimation(.appSpring) { _ = service.copyLastSet(in: workout) }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(.white.opacity(0.16), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ajouter une série identique")
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            if let end = workout.restEndsAt, let start = sets.last?.completedAt, end > .now {
                RestBar(start: start, end: end)
            }
        }
        .padding(18)
        .background(Palette.text, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
    }
}

/// 6 pt rest progress with "Repos 0:54".
struct RestBar: View {
    let start: Date
    let end: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let total = max(1, end.timeIntervalSince(start))
            let left = max(0, end.timeIntervalSince(context.date))
            HStack(spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule()
                            .fill(Palette.green)
                            .frame(width: proxy.size.width * (1 - left / total))
                    }
                }
                .frame(height: 6)
                Text("Repos \(Int(left) / 60):\(String(format: "%02d", Int(left) % 60))")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

/// One exercise of the session: done (check, struck, summary), current, or to come (target).
struct WorkoutEntryRow: View {
    let entry: WorkoutEntry
    var isCurrent: Bool

    private var sets: [WorkoutSet] { entry.sortedSets }
    private var isDone: Bool {
        guard !isCurrent, !sets.isEmpty else { return false }
        return true
    }

    private var subtitle: String {
        guard let exercise = entry.exercise else { return "" }
        if isDone { return GymMath.summary(sets.map(\.value), kind: exercise.kind) }
        if isCurrent {
            let target = entry.targetSets.map { " / \($0)" } ?? ""
            let noun = (entry.targetSets ?? sets.count) > 1 ? "séries" : "série"
            return "en cours · \(sets.count)\(target) \(noun)"
        }
        guard let targetSets = entry.targetSets, let targetReps = entry.targetReps else { return "à faire" }
        let weight = entry.targetWeight.map { " · \(GymMath.kg($0)) kg" } ?? ""
        return "\(targetSets) × \(targetReps)\(weight)"
    }

    var body: some View {
        HStack(spacing: 12) {
            CheckCircle(isOn: isDone, size: 22)
                .overlay {
                    if isCurrent {
                        Circle().strokeBorder(Palette.green, lineWidth: 2)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.exercise?.nameFR ?? "Exercice")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .strikethrough(isDone)
                Text(subtitle)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? Palette.green : Palette.secondary)
            }
            Spacer(minLength: 0)
            if sets.contains(where: \.isPR) {
                Text("PR")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Palette.green)
            }
        }
        .opacity(isDone ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Edit reps / weight (or time / distance) of a set, or delete it.
struct SetEditSheet: View {
    let set: WorkoutSet

    @Environment(\.dismiss) private var dismiss
    @State private var reps: Int
    @State private var weight: Double
    @State private var seconds: Int
    @State private var meters: Double

    init(set: WorkoutSet) {
        self.set = set
        _reps = State(initialValue: set.reps ?? 0)
        _weight = State(initialValue: set.weightKg ?? 0)
        _seconds = State(initialValue: Int(set.seconds ?? 0))
        _meters = State(initialValue: set.meters ?? 0)
    }

    private var kind: ExerciseKind { self.set.entry?.exercise?.kind ?? .weightReps }

    var body: some View {
        NavigationStack {
            Form {
                switch kind {
                case .weightReps, .bodyweightReps:
                    Stepper("Répétitions : \(reps)", value: $reps, in: 0...100)
                    HStack {
                        Text(kind == .bodyweightReps ? "Lest" : "Charge")
                        Spacer()
                        Button("−2,5") { weight = max(0, weight - 2.5) }.buttonStyle(.bordered)
                        TextField("0", value: $weight, format: .number.locale(.app))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 64)
                        Text("kg").foregroundStyle(Palette.secondary)
                        Button("+2,5") { weight += 2.5 }.buttonStyle(.bordered)
                    }
                case .time:
                    Stepper("Durée : \(seconds / 60):\(String(format: "%02d", seconds % 60))", value: $seconds, in: 0...7200, step: 15)
                case .distance:
                    HStack {
                        Text("Distance")
                        Spacer()
                        TextField("0", value: $meters, format: .number.locale(.app))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("m").foregroundStyle(Palette.secondary)
                    }
                }
                Section {
                    Button("Supprimer la série", role: .destructive) {
                        GymService.shared.delete(set)
                        dismiss()
                    }
                }
            }
            .navigationTitle(set.entry?.exercise?.nameFR ?? "Série")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", role: .confirm) {
                        switch kind {
                        case .weightReps, .bodyweightReps:
                            GymService.shared.update(set, reps: reps, weight: weight > 0 ? weight : nil)
                        case .time:
                            GymService.shared.update(set, reps: nil, weight: nil, seconds: Double(seconds))
                        case .distance:
                            GymService.shared.update(set, reps: nil, weight: nil, meters: meters)
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// End of workout: duration, volume, records.
struct WorkoutSummaryView: View {
    let summary: WorkoutSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Durée", value: TimeFormat.short(summary.duration))
                    LabeledContent("Volume", value: GymMath.volumeLabel(summary.volume))
                    LabeledContent("Séries", value: "\(summary.setCount)")
                }
                Section(summary.records.isEmpty ? "Aucun record cette fois" : "Records battus") {
                    ForEach(summary.records, id: \.self) { record in
                        Label(record, systemImage: "trophy.fill")
                            .foregroundStyle(Palette.text)
                            .symbolRenderingMode(.multicolor)
                    }
                }
            }
            .navigationTitle(summary.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", role: .confirm) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
