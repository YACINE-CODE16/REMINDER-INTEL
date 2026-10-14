import SwiftUI
import SwiftData

/// Every active goal, grouped by space; groups and goals ordered by urgency.
struct GoalsOverview: View {
    @Query private var goals: [Goal]
    @Query private var sessions: [Session]
    @State private var editedGoal: Goal?

    private struct Group: Identifiable {
        let space: Space
        let goals: [Goal]
        var id: UUID { space.id }
    }

    private var groups: [Group] {
        let now = Date.now
        let sorted = GoalMath.sortedByUrgency(goals.filter { !$0.isArchived && $0.space != nil }, sessions: sessions, now: now)
        var order: [UUID] = []
        var bySpace: [UUID: (Space, [Goal])] = [:]
        for goal in sorted {
            guard let space = goal.space else { continue }
            if bySpace[space.id] == nil { order.append(space.id) }
            bySpace[space.id, default: (space, [])].1.append(goal)
        }
        return order.compactMap { id in bySpace[id].map { Group(space: $0.0, goals: $0.1) } }
    }

    var body: some View {
        List {
            Text("Objectifs")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Palette.text)
                .glassListRow(top: 4)
            if groups.isEmpty {
                Text("Aucun objectif actif. Ajoute-en depuis un espace.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondary)
                    .glassListRow(top: 12)
            }
            ForEach(groups) { group in
                HStack(spacing: 8) {
                    SpaceBadge(space: group.space, size: 24)
                    Text(group.space.displayPath)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.text)
                }
                .glassListRow(top: 16)
                ForEach(group.goals) { goal in
                    GoalRow(goal: goal, sessions: sessions) { editedGoal = goal }
                        .glassListRow(top: 4, bottom: 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                withAnimation(.appSpring) { goal.isArchived = true }
                                try? goal.modelContext?.save()
                            } label: {
                                Label("Archiver", systemImage: "archivebox")
                            }
                            .tint(Palette.secondary)
                        }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 12, for: .scrollContent)
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editedGoal) { goal in
            GoalFormView(goal: goal)
        }
    }
}
