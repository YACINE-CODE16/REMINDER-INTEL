import SwiftUI
import SwiftData

/// One space: its direct children as chips (tap = navigate), objectives placeholder, and the
/// tasks of the space and all its descendants by due date.
struct SpaceDetailView: View {
    let space: Space
    var onSelectTask: (TaskItem) -> Void

    @AppStorage(AppStorageKey.defaultRepeatInterval) private var defaultRepeatInterval: RepeatInterval = .every15min
    @Query private var allTasks: [TaskItem]
    @State private var showsFinished = false
    @State private var isAddingTask = false

    /// Tasks filed in this space or below. Queried rather than read from the relationship
    /// so status changes refresh the list.
    private var subtreeTasks: [TaskItem] {
        allTasks.filter { $0.space.map(space.contains) ?? false }
    }

    private var pending: [TaskItem] {
        subtreeTasks.filter { $0.status == .pending }.sorted(by: TaskItem.byDueDate)
    }

    private var finished: [TaskItem] {
        subtreeTasks.filter { $0.status != .pending }
            .sorted { ($0.dueDate ?? $0.createdAt) > ($1.dueDate ?? $1.createdAt) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if !space.sortedChildren.isEmpty {
                    chips
                }
                objectives
                tasksSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingTask = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Nouvelle tâche dans \(space.name)")
            }
        }
        .sheet(isPresented: $isAddingTask) {
            TaskFormView(
                initialDate: TaskFormView.suggestedDueDate(on: .now),
                repeatInterval: defaultRepeatInterval,
                isReminder: false,
                hasDueDate: false,
                space: space
            )
        }
    }

    // MARK: - Header

    private var subtitle: String {
        let count = pending.count
        let overdue = pending.filter { $0.isOverdue() }.count
        var text = SpaceCard.taskCount(count)
        if overdue > 0 { text += " · \(overdue) en retard" }
        if let parent = space.parent { text = "\(parent.displayPath) · " + text }
        return text
    }

    private var header: some View {
        HStack(spacing: 14) {
            SpaceBadge(space: space, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(space.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Palette.text)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    // MARK: - Chips

    private var chips: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Text("Tout")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Palette.text, in: .capsule)
                        .accessibilityAddTraits(.isSelected)

                    ForEach(space.sortedChildren) { child in
                        NavigationLink(value: child) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(child.color)
                                    .frame(width: 8, height: 8)
                                Text(child.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Palette.text)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.tint(.white.opacity(0.55)).interactive(), in: .capsule)
                        .glassRim(.capsule)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    // MARK: - Objectives (step 6c)

    private var objectives: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Objectifs") {
                Button("Ajouter") {}
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.blue)
                    .disabled(true)
                    .opacity(0.5)
            }
            GlassCard(padding: 14) {
                Label("Les objectifs arrivent bientôt.", systemImage: "target")
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    // MARK: - Tasks

    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Tâches") {
                Text("par échéance")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            }

            if pending.isEmpty {
                Text("Aucune tâche en cours")
                    .font(.callout)
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            ForEach(pending) { item in
                SpaceTaskRow(item: item, rootSpace: space, onSelect: onSelectTask)
            }

            if !finished.isEmpty {
                Button {
                    withAnimation(.appSpring) { showsFinished.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Terminées (\(finished.count))")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(showsFinished ? 0 : -90))
                        Spacer()
                    }
                    .foregroundStyle(Palette.secondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                if showsFinished {
                    ForEach(finished) { item in
                        SpaceTaskRow(item: item, rootSpace: space, onSelect: onSelectTask)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Palette.text)
            Spacer()
            trailing()
        }
    }
}

/// Task card inside a space: check circle, title, "Sous-espace · échéance".
struct SpaceTaskRow: View {
    let item: TaskItem
    let rootSpace: Space
    var onSelect: (TaskItem) -> Void

    private var isFinished: Bool { item.status != .pending }
    private var isOverdue: Bool { item.isOverdue() }

    private var subtitle: String {
        var parts: [String] = []
        if let space = item.space, let relative = rootSpace.relativePath(of: space) {
            parts.append(relative)
        }
        parts.append(item.dueDate.map(Self.dueLabel) ?? "sans date")
        if item.isReminder { parts.append("rappel") }
        return parts.joined(separator: " · ")
    }

    /// "aujourd'hui 18:00", "demain 10:00", "jeu. 16 oct. 14:00".
    static func dueLabel(_ date: Date) -> String {
        let calendar = Calendar.app
        let time = date.formatted(.dateTime.hour().minute().locale(.app))
        if calendar.isDateInToday(date) { return "aujourd'hui \(time)" }
        if calendar.isDateInTomorrow(date) { return "demain \(time)" }
        if calendar.isDateInYesterday(date) { return "hier \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(.app))) \(time)"
    }

    var body: some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                checkCircle
                Button {
                    onSelect(item)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.text)
                            .strikethrough(isFinished)
                            .lineLimit(2)
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(isOverdue ? Palette.red : Palette.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(isFinished ? 0.6 : 1)
    }

    /// Tap: pending → done, finished → pending again.
    private var checkCircle: some View {
        Button {
            withAnimation(.appSpring) {
                NotificationService.shared.setStatus(isFinished ? .pending : .done, for: item)
            }
        } label: {
            ZStack {
                if item.status == .done {
                    Circle().fill(Palette.green)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .strokeBorder(isOverdue ? Palette.red : Palette.secondary.opacity(0.5), lineWidth: 1.5)
                }
            }
            .frame(width: 22, height: 22)
            .frame(width: 34, height: 34)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFinished ? "Remettre à faire" : "Marquer comme faite")
    }
}
