import SwiftUI
import SwiftData

/// Suivi tab: running session (or start card), today's time per root space, today's sessions.
struct TrackingView: View {
    @Binding var showsStats: Bool

    @Query(sort: \Session.startedAt) private var sessions: [Session]
    @Query private var spaces: [Space]
    @State private var editedSession: Session?
    @State private var isAddingSession = false
    @State private var isPickingSpace = false

    private let tracking = TrackingService.shared
    private let calendar = Calendar.app

    private var active: Session? { sessions.last(where: \.isActive) }

    private var todaySessions: [Session] {
        let today = TimeTotals.day(containing: .now)
        return sessions.filter { $0.overlap(with: today) > 0 || ($0.isActive && $0.startedAt >= today.start) }
    }

    /// Last 3 distinct spaces with a session, then the first roots.
    private var recentSpaces: [Space] {
        var result: [Space] = []
        for session in sessions.reversed() {
            guard let space = session.space, !space.isArchived, !result.contains(where: { $0.id == space.id }) else { continue }
            result.append(space)
            if result.count == 3 { return result }
        }
        for root in Space.roots(of: spaces) where result.count < 3 && !result.contains(where: { $0.id == root.id }) {
            result.append(root)
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                header
                    .glassListRow(top: 8)
                Group {
                    if let active {
                        RunningSessionCard(session: active) { tracking.stop() }
                    } else {
                        startCard
                    }
                }
                .glassListRow(bottom: 12)

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    todaySection(now: context.date)
                }
                .glassListRow()

                sessionsHeader
                    .glassListRow(top: 16)
                if todaySessions.isEmpty {
                    Text("Aucune session aujourd'hui")
                        .font(.callout)
                        .foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glassListRow()
                }
                ForEach(todaySessions.reversed()) { session in
                    Button {
                        editedSession = session
                    } label: {
                        SessionRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .glassListRow(top: 4, bottom: 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(.appSpring) { tracking.delete(session) }
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        .tint(Palette.red)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 12, for: .scrollContent)
            .background(AppBackground())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showsStats) {
                StatsView()
            }
        }
        .sheet(item: $editedSession) { session in
            SessionFormView(session: session)
        }
        .sheet(isPresented: $isAddingSession) {
            SessionFormView(space: recentSpaces.first)
        }
        .sheet(isPresented: $isPickingSpace) {
            SpacePickerSheet(title: "Démarrer dans…", allowsNone: false) { space in
                if let space { tracking.start(in: space) }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(.app)).uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                Text("Suivi")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Palette.text)
            }
            Spacer()
            Button {
                showsStats = true
            } label: {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Palette.text)
                    .frame(width: 48, height: 48)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassRim(.circle)
            .accessibilityLabel("Statistiques")
        }
    }

    // MARK: - Start card

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Palette.green, in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Démarrer")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Palette.text)
                    Text("Choisis un espace ou dicte « je commence… »")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.secondary)
                }
            }
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(recentSpaces) { space in
                            Button {
                                withAnimation(.appSpring) { _ = tracking.start(in: space) }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(space.color).frame(width: 8, height: 8)
                                    Text(space.name)
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
                            .accessibilityLabel("Démarrer \(space.name)")
                        }
                        Button {
                            isPickingSpace = true
                        } label: {
                            Text("Autre…")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.secondary)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .padding(.vertical, 2)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(.white.opacity(0.55)), in: .rect(cornerRadius: 28))
        .glassRim(.rect(cornerRadius: 28))
        .softShadow()
    }

    // MARK: - Today

    private func todaySection(now: Date) -> some View {
        let today = TimeTotals.day(containing: now)
        let roots = TimeTotals.byRoot(sessions, in: today, now: now)
        let total = roots.reduce(0) { $0 + $1.seconds }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Aujourd'hui")
                    .font(.title3.bold())
                    .foregroundStyle(Palette.text)
                Spacer()
                Text("\(TimeFormat.short(total)) au total")
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            }
            if roots.isEmpty {
                Text("Rien de tracké pour l'instant")
                    .font(.callout)
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            ForEach(roots, id: \.space.id) { entry in
                GlassCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Circle().fill(entry.space.color).frame(width: 10, height: 10)
                            Text(entry.space.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Text(TimeFormat.short(entry.seconds))
                                .font(.system(size: 15, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.text)
                        }
                        ProgressBar(fraction: total > 0 ? entry.seconds / total : 0, color: entry.space.color)
                    }
                }
            }
        }
    }

    private var sessionsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Sessions")
                .font(.title3.bold())
                .foregroundStyle(Palette.text)
            Spacer()
            Button("Ajouter") { isAddingSession = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.blue)
                .buttonStyle(.plain)
        }
    }
}

/// Black card of the running session: badge, "EN COURS · ÉTUDES", live chrono, red Stop.
struct RunningSessionCard: View {
    let session: Session
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let space = session.space {
                SpaceBadge(space: space, size: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("EN COURS · \((session.space?.pathComponents ?? []).joined(separator: " · ").uppercased())")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Text(timerInterval: session.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            Button(action: onStop) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white)
                    .frame(width: 18, height: 18)
                    .frame(width: 52, height: 52)
                    .background(Palette.red, in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Arrêter la session")
        }
        .padding(18)
        .background(Palette.text, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
    }
}

/// Light glass row: time range, divider, "Espace · note", duration.
struct SessionRow: View {
    let session: Session

    private var label: String {
        let name = session.space?.name ?? "Sans espace"
        guard let note = session.note, !note.isEmpty else { return name }
        return "\(name) · \(note)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(TimeFormat.range(session))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Palette.secondary)
                .frame(width: 92, alignment: .leading)
            Capsule()
                .fill(session.space?.color ?? Palette.secondary.opacity(0.3))
                .frame(width: 3, height: 28)
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if session.isActive {
                Text(timerInterval: session.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.green)
                    .frame(maxWidth: 70, alignment: .trailing)
            } else {
                Text(TimeFormat.short(session.duration()))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.text)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.white.opacity(0.3)), in: .rect(cornerRadius: 18))
        .glassRim(.rect(cornerRadius: 18), opacity: 0.7)
        .contentShape(.rect(cornerRadius: 18))
    }
}

/// 6 pt capsule bar in a space colour.
struct ProgressBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.text.opacity(0.07))
                Capsule()
                    .fill(color)
                    .frame(width: max(6, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
