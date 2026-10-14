import SwiftUI
import SwiftData

/// Goal card: title, value on the right, 6 pt bar for hours and count, +1 for count;
/// outcome goals show their deadline and foldable steps with check circles.
struct GoalRow: View {
    let goal: Goal
    let sessions: [Session]
    var showsSpace = false
    var onEdit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var showsSteps = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let achieved = GoalMath.isAchieved(goal, sessions: sessions, now: now)
        let color = goal.space?.color ?? Palette.secondary
        return GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    if goal.kind == .outcome {
                        achievedCircle
                            .padding(.top, -2)
                    }
                    Button(action: onEdit) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.text)
                                .strikethrough(goal.kind == .outcome && goal.isAchieved)
                                .lineLimit(2)
                            if showsSpace, let space = goal.space {
                                Text(space.displayPath)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.secondary)
                            } else if let period = goal.period.shortLabel, goal.kind != .outcome {
                                Text("Objectif \(period == "sem." ? "de la semaine" : "du mois")")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)

                    Text(GoalMath.valueLabel(goal, sessions: sessions, now: now))
                        .font(.system(size: 14, weight: goal.kind == .outcome ? .regular : .bold))
                        .monospacedDigit()
                        .foregroundStyle(valueColor(achieved: achieved, now: now))
                    if goal.kind == .count {
                        plusOne
                    }
                }
                if goal.kind != .outcome {
                    ProgressBar(fraction: GoalMath.fraction(goal, sessions: sessions, now: now), color: achieved ? Palette.green : color)
                } else if !goal.steps.isEmpty {
                    stepsSection
                }
            }
        }
        .opacity(goal.kind == .outcome && goal.isAchieved ? 0.6 : 1)
    }

    private func valueColor(achieved: Bool, now: Date) -> Color {
        if achieved { return Palette.green }
        if goal.kind == .outcome, let deadline = goal.deadline, deadline < now { return Palette.red }
        return goal.kind == .outcome ? Palette.secondary : Palette.text
    }

    private var achievedCircle: some View {
        Button {
            withAnimation(.appSpring) {
                goal.isAchieved.toggle()
                goal.achievedAt = goal.isAchieved ? .now : nil
                try? modelContext.save()
            }
        } label: {
            CheckCircle(isOn: goal.isAchieved, size: 22)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(goal.isAchieved ? "Marquer non atteint" : "Marquer atteint")
    }

    private var plusOne: some View {
        Button {
            withAnimation(.appSpring) {
                GoalMath.increment(goal)
                try? modelContext.save()
            }
        } label: {
            Text("+1")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Palette.text)
                .frame(width: 40, height: 28)
                .contentShape(.capsule)
                .padding(.top, -6)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.white.opacity(0.5)).interactive(), in: .capsule)
        .glassRim(.capsule)
        .sensoryFeedback(.increase, trigger: goal.currentManual)
        .accessibilityLabel("Ajouter 1 à \(goal.title)")
    }

    @ViewBuilder
    private var stepsSection: some View {
        let done = goal.steps.filter(\.isDone).count
        Button {
            withAnimation(.appSpring) { showsSteps.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text("\(done)/\(goal.steps.count) étapes")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(showsSteps ? 0 : -90))
                Spacer()
            }
            .foregroundStyle(Palette.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        if showsSteps {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(goal.sortedSteps) { step in
                    Button {
                        withAnimation(.appSpring) {
                            step.isDone.toggle()
                            try? modelContext.save()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            CheckCircle(isOn: step.isDone, size: 18)
                            Text(step.title)
                                .font(.system(size: 13))
                                .foregroundStyle(step.isDone ? Palette.secondary : Palette.text)
                                .strikethrough(step.isDone)
                            Spacer()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 4)
        }
    }
}

/// Green filled circle with a check when on, grey ring otherwise.
struct CheckCircle: View {
    var isOn: Bool
    var size: CGFloat

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Palette.green)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Palette.secondary.opacity(0.5), lineWidth: 1.5)
            }
        }
        .frame(width: size, height: size)
    }
}

/// One line under a hub card: short label on 118 pt, 6 pt bar, value in bold.
struct GoalCompactLine: View {
    let goal: Goal
    let sessions: [Session]

    var body: some View {
        let now = Date.now
        HStack(spacing: 8) {
            Text(goal.title)
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .frame(width: 118, alignment: .leading)
            if goal.kind == .outcome && goal.steps.isEmpty {
                Spacer(minLength: 0)
            } else {
                ProgressBar(
                    fraction: GoalMath.fraction(goal, sessions: sessions, now: now),
                    color: GoalMath.isAchieved(goal, sessions: sessions, now: now) ? Palette.green : (goal.space?.color ?? Palette.secondary)
                )
            }
            Text(compactValue(now: now))
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    /// "62 %", "3/10", or the deadline for an outcome.
    private func compactValue(now: Date) -> String {
        switch goal.kind {
        case .hours:
            return "\(Int((GoalMath.fraction(goal, sessions: sessions, now: now) * 100).rounded())) %"
        case .count:
            return "\(GoalMath.number(GoalMath.count(goal, now: now)))/\(GoalMath.number(goal.target))"
        case .outcome:
            if goal.isAchieved { return "Atteint" }
            return goal.deadline.map { $0.formatted(.dateTime.day().month(.abbreviated).locale(.app)) } ?? "—"
        }
    }
}

/// New or edited goal: title, space, kind, target, unit, period or deadline, steps.
struct GoalFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let goal: Goal?
    @State private var title: String
    @State private var space: Space?
    @State private var kind: GoalKind
    @State private var target: Double
    @State private var unit: String
    @State private var period: GoalPeriod
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var counter: Double
    @State private var steps: [String]
    @State private var newStep = ""

    private static let rowBackground = Color.white.opacity(0.7)

    init(space: Space?) {
        goal = nil
        _title = State(initialValue: "")
        _space = State(initialValue: space)
        _kind = State(initialValue: .hours)
        _target = State(initialValue: 10)
        _unit = State(initialValue: "")
        _period = State(initialValue: .week)
        _hasDeadline = State(initialValue: false)
        _deadline = State(initialValue: Calendar.app.date(byAdding: .month, value: 1, to: .now) ?? .now)
        _counter = State(initialValue: 0)
        _steps = State(initialValue: [])
    }

    init(goal: Goal) {
        self.goal = goal
        _title = State(initialValue: goal.title)
        _space = State(initialValue: goal.space)
        _kind = State(initialValue: goal.kind)
        _target = State(initialValue: goal.target)
        _unit = State(initialValue: goal.unit ?? "")
        _period = State(initialValue: goal.period)
        _hasDeadline = State(initialValue: goal.deadline != nil)
        _deadline = State(initialValue: goal.deadline ?? (Calendar.app.date(byAdding: .month, value: 1, to: .now) ?? .now))
        _counter = State(initialValue: GoalMath.count(goal, now: .now))
        _steps = State(initialValue: goal.sortedSteps.map(\.title))
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && space != nil && (kind == .outcome || target > 0)
    }

    /// An outcome or an "until a date" goal has a deadline.
    private var usesDeadline: Bool { kind == .outcome ? hasDeadline : period == .untilDate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title)
                    SpacePickerRow(selection: $space, allowsNone: false)
                }
                .listRowBackground(Self.rowBackground)

                Section {
                    Picker("Type", selection: $kind.animation(.appSpring)) {
                        ForEach(GoalKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                } footer: {
                    Text(kindHint)
                }
                .listRowBackground(Self.rowBackground)

                if kind != .outcome {
                    Section {
                        HStack {
                            Text("Cible")
                            Spacer()
                            TextField("10", value: $target, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            if kind == .hours {
                                Text("h").foregroundStyle(Palette.secondary)
                            }
                        }
                        if kind == .count {
                            TextField("Unité (séances, clubs…)", text: $unit)
                            if goal != nil {
                                Stepper("Actuel : \(GoalMath.number(counter))", value: $counter, in: 0...10_000)
                            }
                        }
                        Picker("Période", selection: $period.animation(.appSpring)) {
                            ForEach(GoalPeriod.allCases) { Text($0.label).tag($0) }
                        }
                    }
                    .listRowBackground(Self.rowBackground)
                }

                Section {
                    if kind == .outcome {
                        Toggle("Échéance", isOn: $hasDeadline.animation(.appSpring))
                    }
                    if usesDeadline {
                        DatePicker("Date", selection: $deadline, displayedComponents: .date)
                    }
                }
                .listRowBackground(Self.rowBackground)

                if kind == .outcome {
                    Section("Sous-étapes") {
                        ForEach(steps.indices, id: \.self) { index in
                            TextField("Étape", text: $steps[index])
                        }
                        .onDelete { steps.remove(atOffsets: $0) }
                        .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                        HStack {
                            TextField("Nouvelle étape", text: $newStep)
                                .onSubmit(addStep)
                            Button("Ajouter", action: addStep)
                                .disabled(newStep.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .listRowBackground(Self.rowBackground)
                }

                if let goal {
                    Section {
                        Button(goal.isArchived ? "Désarchiver" : "Archiver") {
                            goal.isArchived.toggle()
                            try? modelContext.save()
                            dismiss()
                        }
                        .foregroundStyle(Palette.secondary)
                    }
                    .listRowBackground(Self.rowBackground)
                }
            }
            .tint(Palette.green)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(goal == nil ? "Nouvel objectif" : "Modifier l'objectif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", role: .confirm) { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var kindHint: String {
        switch kind {
        case .hours: "Calculé à partir des sessions de l'espace et de ses sous-espaces."
        case .count: "Compteur manuel : +1 sur la carte ou « un de plus » à la voix."
        case .outcome: "Résultat à atteindre, avec des sous-étapes et un état atteint à cocher."
        }
    }

    private func addStep() {
        let trimmed = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        steps.append(trimmed)
        newStep = ""
    }

    private func save() {
        guard let space else { return }
        let target = kind == .outcome ? 1 : self.target
        let period = kind == .outcome ? GoalPeriod.untilDate : self.period
        let saved: Goal
        if let goal {
            saved = goal
            goal.title = trimmedTitle
            goal.space = space
            goal.kind = kind
            goal.target = target
            goal.period = period
        } else {
            saved = Goal(space: space, title: trimmedTitle, kind: kind, target: target, period: period)
            modelContext.insert(saved)
        }
        saved.unit = kind == .hours ? "h" : (unit.trimmingCharacters(in: .whitespaces).isEmpty ? nil : unit.trimmingCharacters(in: .whitespaces))
        saved.deadline = usesDeadline ? deadline : nil
        if kind == .count, goal != nil, counter != GoalMath.count(saved, now: .now) {
            GoalMath.increment(saved, by: counter - GoalMath.count(saved, now: .now))
        }
        if kind == .outcome {
            syncSteps(of: saved)
        }
        try? modelContext.save()
        dismiss()
    }

    /// Keeps the done state of steps whose title did not change.
    private func syncSteps(of goal: Goal) {
        let titles = steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        var existing = goal.steps
        for step in existing where !titles.contains(step.title) {
            modelContext.delete(step)
        }
        existing.removeAll { !titles.contains($0.title) }
        for (index, title) in titles.enumerated() {
            if let step = existing.first(where: { $0.title == title }) {
                step.sortOrder = index
            } else {
                let step = GoalStep(title: title, sortOrder: index)
                step.goal = goal
                modelContext.insert(step)
            }
        }
    }
}
