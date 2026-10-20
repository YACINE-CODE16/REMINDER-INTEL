import Charts
import SwiftUI
import SwiftData

/// Searchable exercise list grouped by muscle group.
struct ExerciseList: View {
    var onSelect: (Exercise) -> Void

    @Query(sort: \Exercise.nameFR) private var exercises: [Exercise]
    @State private var query = ""
    @State private var isCreating = false

    private var filtered: [Exercise] {
        let key = SpaceRouter.normalize(query)
        guard !key.isEmpty else { return exercises }
        return exercises.filter { exercise in
            ([exercise.nameFR, exercise.nameEN] + exercise.aliases).contains { SpaceRouter.normalize($0).contains(key) }
        }
    }

    var body: some View {
        List {
            ForEach(MuscleGroup.allCases) { group in
                let items = filtered.filter { $0.muscleGroup == group }
                if !items.isEmpty {
                    Section(group.label) {
                        ForEach(items) { exercise in
                            Button {
                                onSelect(exercise)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.nameFR).foregroundStyle(Palette.text)
                                    Text(exercise.isCustom ? "Personnalisé" : exercise.nameEN)
                                        .font(.caption)
                                        .foregroundStyle(Palette.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Rechercher (FR ou EN)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nouvel exercice")
            }
        }
        .sheet(isPresented: $isCreating) {
            ExerciseFormView()
        }
    }
}

/// Picks an exercise to add to the running workout.
struct ExercisePickerSheet: View {
    var onPick: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseList { exercise in
                onPick(exercise)
                dismiss()
            }
            .navigationTitle("Ajouter un exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
            }
        }
    }
}

/// Library: every exercise, tap = its history and records.
struct ExerciseLibraryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Exercise] = []

    var body: some View {
        NavigationStack(path: $path) {
            ExerciseList { path.append($0) }
                .navigationTitle("Exercices")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close) { dismiss() }
                    }
                }
        }
    }
}

/// New custom exercise.
struct ExerciseFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var nameFR = ""
    @State private var nameEN = ""
    @State private var aliases = ""
    @State private var muscle: MuscleGroup = .other
    @State private var kind: ExerciseKind = .weightReps

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $nameFR)
                TextField("Nom anglais (facultatif)", text: $nameEN)
                TextField("Autres noms dictés, séparés par des virgules", text: $aliases)
                Picker("Groupe", selection: $muscle) {
                    ForEach(MuscleGroup.allCases) { Text($0.label).tag($0) }
                }
                Picker("Type", selection: $kind) {
                    ForEach(ExerciseKind.allCases) { Text($0.label).tag($0) }
                }
            }
            .navigationTitle("Nouvel exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer", role: .confirm) {
                        let name = nameFR.trimmingCharacters(in: .whitespacesAndNewlines)
                        let english = nameEN.trimmingCharacters(in: .whitespacesAndNewlines)
                        let extra = aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                        modelContext.insert(Exercise(
                            id: "custom-\(UUID().uuidString)",
                            nameFR: name,
                            nameEN: english.isEmpty ? name : english,
                            aliases: [name.lowercased()] + extra,
                            muscleGroup: muscle,
                            kind: kind,
                            isCustom: true
                        ))
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(nameFR.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// One exercise: estimated 1RM and heaviest weight over 3 / 6 / 12 months, records, history.
struct ExerciseDetailView: View {
    let exercise: Exercise

    @State private var months = 3
    private let service = GymService.shared

    private var since: Date {
        Calendar.app.date(byAdding: .month, value: -months, to: .now) ?? .now
    }

    var body: some View {
        let _ = service.revision
        let records = service.records(of: exercise)
        let points = service.curve(of: exercise, since: since)
        List {
            if exercise.kind == .weightReps {
                Section {
                    Picker("Période", selection: $months) {
                        Text("3 mois").tag(3)
                        Text("6 mois").tag(6)
                        Text("12 mois").tag(12)
                    }
                    .pickerStyle(.segmented)
                    if points.isEmpty {
                        Text("Pas encore de séance sur cette période.")
                            .foregroundStyle(Palette.secondary)
                    } else {
                        chart(points)
                            .frame(height: 200)
                            .padding(.vertical, 6)
                    }
                }
            }
            Section("Records") {
                if let weight = records.maxWeight {
                    LabeledContent("Charge max", value: "\(GymMath.kg(weight)) kg")
                }
                if let estimate = records.best1RM {
                    LabeledContent("1RM estimé (Epley)", value: "\(GymMath.kg((estimate * 2).rounded() / 2)) kg")
                }
                if let volume = records.maxSessionVolume {
                    LabeledContent("Volume max d'une séance", value: GymMath.volumeLabel(volume))
                }
                if let reps = records.maxReps {
                    LabeledContent("Reps max", value: "\(reps)")
                }
                ForEach(records.maxRepsAtWeight.sorted { $0.key > $1.key }.prefix(3), id: \.key) { weight, reps in
                    LabeledContent("Reps max à \(GymMath.kg(weight)) kg", value: "\(reps)")
                }
                if let seconds = records.maxSeconds {
                    LabeledContent("Durée max", value: GymMath.label(.init(reps: nil, weight: nil, seconds: seconds), kind: .time))
                }
                if let meters = records.maxMeters {
                    LabeledContent("Distance max", value: GymMath.label(.init(reps: nil, weight: nil, meters: meters), kind: .distance))
                }
                if records.isEmpty {
                    Text("Aucune série enregistrée.").foregroundStyle(Palette.secondary)
                }
            }
            Section("Historique") {
                ForEach(exercise.entries.filter { !$0.sets.isEmpty }.sorted { ($0.workout?.startedAt ?? .distantPast) > ($1.workout?.startedAt ?? .distantPast) }) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(GymModuleView.relativeDay(entry.workout?.startedAt ?? .now)) · \(entry.workout?.name ?? "")")
                            .font(.subheadline.weight(.semibold))
                        Text(entry.sortedSets.map { GymMath.label($0.value, kind: exercise.kind) + ($0.isPR ? " PR" : "") }.joined(separator: " · "))
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .navigationTitle(exercise.nameFR)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func chart(_ points: [GymMath.CurvePoint]) -> some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("kg", point.best1RM), series: .value("Mesure", "1RM estimé"))
                    .foregroundStyle(Palette.green)
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value("kg", point.best1RM))
                    .foregroundStyle(Palette.green)
                    .symbolSize(24)
                LineMark(x: .value("Date", point.date), y: .value("kg", point.maxWeight), series: .value("Mesure", "Charge max"))
                    .foregroundStyle(Palette.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartForegroundStyleScale(["1RM estimé": Palette.green, "Charge max": Palette.secondary])
        .chartLegend(position: .top, alignment: .leading)
    }
}
