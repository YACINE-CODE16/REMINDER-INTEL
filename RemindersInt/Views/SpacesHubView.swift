import SwiftUI
import SwiftData

/// Espaces tab: week summary and root spaces. Drag to reorder, swipe to archive.
struct SpacesHubView: View {
    /// Owned by the root view so a space can be opened from outside the tab.
    @Binding var path: [Space]
    /// The task detail sheet is owned by the root view.
    var onSelectTask: (TaskItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var spaces: [Space]
    @Query private var tasks: [TaskItem]
    @Query private var sessions: [Session]
    /// Observed so goal changes refresh the cards.
    @Query private var goals: [Goal]
    @State private var isCreating = false
    @State private var showsArchived = false

    private let calendar = Calendar.app

    private var roots: [Space] { Space.roots(of: spaces) }
    private var archived: [Space] {
        spaces.filter(\.isArchived).sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                header
                    .glassListRow(top: 8)
                summaryCard
                    .glassListRow(bottom: 10)

                ForEach(roots) { space in
                    Button {
                        path.append(space)
                    } label: {
                        SpaceCard(space: space)
                    }
                    .buttonStyle(.plain)
                    .glassListRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            setArchived(true, space)
                        } label: {
                            Label("Archiver", systemImage: "archivebox")
                        }
                        .tint(Palette.secondary)
                    }
                }
                .onMove(perform: moveRoots)

                if !archived.isEmpty {
                    archivedSection
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Space.self) { space in
                SpaceDetailView(space: space, onSelectTask: onSelectTask)
            }
        }
        .sheet(isPresented: $isCreating) {
            SpaceFormView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SEMAINE \(Calendar(identifier: .iso8601).component(.weekOfYear, from: .now))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                Text("Espaces")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Palette.text)
            }
            Spacer()
            Button {
                isCreating = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.text)
                    .frame(width: 48, height: 48)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassRim(.circle)
            .accessibilityLabel("Nouvel espace")
        }
    }

    // MARK: - Week summary

    /// Pending dated tasks due by the end of this week, overdue ones included.
    private var weekCounts: (total: Int, overdue: Int) {
        let now = Date.now
        let end = calendar.dateInterval(of: .weekOfYear, for: now)?.end ?? now
        let due = tasks.filter { $0.status == .pending && ($0.dueDate.map { $0 < end } ?? false) }
        return (due.count, due.filter { $0.isOverdue(now: now) }.count)
    }

    private var summaryCard: some View {
        let counts = weekCounts
        return GlassCard {
            HStack(alignment: .top, spacing: 16) {
                summaryColumn(title: "À faire cette semaine") {
                    Text("\(counts.total)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Palette.text)
                        .contentTransition(.numericText())
                    Text(counts.overdue == 0 ? "aucune en retard" : "dont \(counts.overdue) en retard")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(counts.overdue == 0 ? Palette.secondary : Palette.red)
                }
                Rectangle()
                    .fill(Palette.secondary.opacity(0.25))
                    .frame(width: 1)
                summaryColumn(title: "Temps tracké") {
                    let time = weekTime
                    Text(TimeFormat.short(time.current))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Palette.text)
                    Text("\(TimeFormat.delta(time.delta)) vs sem. dernière")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(time.delta >= 0 ? Palette.green : Palette.red)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// This week so far, and the difference with last week at the same point in time.
    private var weekTime: (current: TimeInterval, delta: TimeInterval) {
        let now = Date.now
        let week = TimeTotals.week(containing: now)
        let elapsed = now.timeIntervalSince(week.start)
        let current = TimeTotals.seconds(sessions, in: DateInterval(start: week.start, end: now), now: now)
        let lastStart = calendar.date(byAdding: .day, value: -7, to: week.start) ?? week.start
        let previous = TimeTotals.seconds(sessions, in: DateInterval(start: lastStart, duration: elapsed), now: now)
        return (current, current - previous)
    }

    private func summaryColumn(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Archived

    @ViewBuilder
    private var archivedSection: some View {
        Button {
            withAnimation(.appSpring) { showsArchived.toggle() }
        } label: {
            HStack {
                Text("Archivés (\(archived.count))")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(showsArchived ? 0 : -90))
                Spacer()
            }
            .foregroundStyle(Palette.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassListRow(top: 14)

        if showsArchived {
            ForEach(archived) { space in
                SpaceCard(space: space)
                    .opacity(0.6)
                    .glassListRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            setArchived(false, space)
                        } label: {
                            Label("Restaurer", systemImage: "arrow.uturn.backward")
                        }
                        .tint(Palette.green)
                    }
            }
        }
    }

    // MARK: - Actions

    private func moveRoots(from source: IndexSet, to destination: Int) {
        var ordered = roots
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, space) in ordered.enumerated() {
            space.sortOrder = index
        }
        try? modelContext.save()
    }

    private func setArchived(_ isArchived: Bool, _ space: Space) {
        withAnimation(.appSpring) {
            space.isArchived = isArchived
            if !isArchived, space.parent == nil {
                space.sortOrder = (roots.map(\.sortOrder).max() ?? -1) + 1
            }
        }
        try? modelContext.save()
    }
}

/// Glass card of a space: colour badge, name, counts, overdue badge or chevron.
struct SpaceCard: View {
    let space: Space

    private var counts: (children: Int, pending: Int, overdue: Int, week: TimeInterval) {
        let now = Date.now
        let pending = space.subtreeTasks.filter { $0.status == .pending }
        let week = TimeTotals.seconds(space.subtree.flatMap(\.sessions), in: TimeTotals.week(containing: now), now: now)
        return (space.sortedChildren.count, pending.count, pending.filter { $0.isOverdue(now: now) }.count, week)
    }

    /// "aucune tâche", "1 tâche", "5 tâches".
    static func taskCount(_ count: Int) -> String {
        switch count {
        case 0: "aucune tâche"
        case 1: "1 tâche"
        default: "\(count) tâches"
        }
    }

    private var subtitle: String {
        let counts = counts
        var parts: [String] = []
        if counts.children > 0 {
            parts.append(counts.children == 1 ? "1 sous-espace" : "\(counts.children) sous-espaces")
        }
        parts.append(Self.taskCount(counts.pending))
        if counts.week >= 60 {
            parts.append("\(TimeFormat.short(counts.week)) cette semaine")
        }
        return parts.joined(separator: " · ")
    }

    /// Most urgent active goal of the subtree: nearest deadline, else the most behind its period.
    private var urgentGoal: (goal: Goal, sessions: [Session])? {
        let sessions = space.subtree.flatMap(\.sessions)
        guard let goal = GoalMath.sortedByUrgency(space.subtreeGoals, sessions: sessions, now: .now).first else { return nil }
        return (goal, sessions)
    }

    var body: some View {
        let overdue = counts.overdue
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                SpaceBadge(space: space)
                VStack(alignment: .leading, spacing: 2) {
                    Text(space.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.text)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 8)
                if overdue > 0 {
                    Text("\(overdue) en retard")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Palette.red.opacity(0.12), in: .capsule)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                }
            }
            // Full card width under the name, so the bar keeps its length next to a badge.
            if let urgent = urgentGoal {
                GoalCompactLine(goal: urgent.goal, sessions: urgent.sessions)
                    .padding(.leading, 52)
            }
            }
        }
        .contentShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    SpacesHubView(path: .constant([]), onSelectTask: { _ in })
        .modelContainer(for: [TaskItem.self, Space.self, Session.self, Goal.self], inMemory: true)
}
