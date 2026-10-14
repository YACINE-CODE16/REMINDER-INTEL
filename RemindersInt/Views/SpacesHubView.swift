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
                    .hubRow(top: 8)
                summaryCard
                    .hubRow(bottom: 10)

                ForEach(roots) { space in
                    Button {
                        path.append(space)
                    } label: {
                        SpaceCard(space: space)
                    }
                    .buttonStyle(.plain)
                    .hubRow()
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
                    Text("—")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Palette.secondary)
                    Text("avec le Suivi")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
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
        .hubRow(top: 14)

        if showsArchived {
            ForEach(archived) { space in
                SpaceCard(space: space)
                    .opacity(0.6)
                    .hubRow()
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

    private var counts: (children: Int, pending: Int, overdue: Int) {
        let now = Date.now
        let pending = space.subtreeTasks.filter { $0.status == .pending }
        return (space.sortedChildren.count, pending.count, pending.filter { $0.isOverdue(now: now) }.count)
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
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let overdue = counts.overdue
        GlassCard(padding: 14) {
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
        }
        .contentShape(.rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    /// Transparent full-width list row for the glass layout.
    func hubRow(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: top, leading: 20, bottom: bottom, trailing: 20))
    }
}

#Preview {
    SpacesHubView(path: .constant([]), onSelectTask: { _ in })
        .modelContainer(for: [TaskItem.self, Space.self], inMemory: true)
}
