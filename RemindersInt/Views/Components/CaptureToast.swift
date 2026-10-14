import SwiftUI

/// A session dictated without a confident space, created once the user picks one.
struct PendingSession {
    /// True for "j'ai fait 2h…", false for "je commence…".
    var isLog: Bool
    var start: Date
    var end: Date?
}

/// Result of a dictation, shown in the capture toast.
struct CaptureOutcome: Identifiable {
    enum Kind {
        case task(TaskItem)
        case sessionStarted(Session)
        /// nil when no session was running.
        case sessionStopped(Session?)
        case sessionLogged([Session])
        case pendingSession(PendingSession)
        /// +1 done, can be undone from the toast.
        case goalProgress(Goal)
        case goalUndone(Goal)
        /// Several counters match: the toast asks which one.
        case goalChoice([Goal])
        case goalNotFound
    }

    let id = UUID()
    var kind: Kind
    let transcript: String
    /// Suggested spaces when the parser was not confident enough; empty once filed.
    var proposals: [Space]

    var asksForSpace: Bool {
        switch kind {
        case .task(let item): item.space == nil && !proposals.isEmpty
        case .pendingSession: true
        default: false
        }
    }

    /// Only tasks may stay without a space.
    var allowsNone: Bool {
        if case .task = kind { return true }
        return false
    }

    var canChangeSpace: Bool {
        switch kind {
        case .task, .sessionStarted, .sessionLogged: !asksForSpace
        default: false
        }
    }

    /// Waits for an answer: shown longer.
    var asksQuestion: Bool {
        if case .goalChoice = kind { return true }
        return asksForSpace
    }

    var canUndo: Bool {
        if case .goalProgress = kind { return true }
        return false
    }

    var currentSpace: Space? {
        switch kind {
        case .task(let item): item.space
        case .sessionStarted(let session): session.space
        case .sessionLogged(let sessions): sessions.first?.space
        case .sessionStopped(let session): session?.space
        default: nil
        }
    }
}

/// Black capsule above the tab bar: what was created and where, with "Changer",
/// or "Dans quel espace ?" with 3 suggestions (and "Aucun" for a task).
struct CaptureToastView: View {
    let outcome: CaptureOutcome
    var onPick: (Space?) -> Void
    var onChange: () -> Void
    var onPickGoal: (Goal) -> Void = { _ in }
    var onUndo: () -> Void = {}

    private static let timeStyle = Date.FormatStyle.dateTime.hour().minute().locale(.app)

    private var headline: String {
        switch outcome.kind {
        case .task(let item):
            let kind = item.isReminder ? "Rappel ajouté" : "Tâche ajoutée"
            if outcome.asksForSpace { return "\(kind) · Dans quel espace ?" }
            guard let space = item.space else { return "\(kind), sans espace" }
            return "\(kind) dans \(space.displayPath)"
        case .sessionStarted(let session):
            return "Session démarrée · \(session.space?.displayPath ?? "")"
        case .sessionStopped(let session):
            guard let session else { return "Aucune session en cours" }
            return "Session arrêtée · \(session.space?.displayPath ?? "") · \(TimeFormat.short(session.duration()))"
        case .sessionLogged(let sessions):
            let total = sessions.reduce(0) { $0 + $1.duration() }
            return "\(TimeFormat.short(total)) ajoutées à \(sessions.first?.space?.displayPath ?? "")"
        case .pendingSession(let pending):
            guard pending.isLog, let end = pending.end else { return "Session · Dans quel espace ?" }
            return "\(TimeFormat.short(end.timeIntervalSince(pending.start))) à classer · Dans quel espace ?"
        case .goalProgress(let goal):
            return "+1 · \(goal.title)"
        case .goalUndone(let goal):
            return "+1 annulé · \(goal.title)"
        case .goalChoice:
            return "+1 · Quel objectif ?"
        case .goalNotFound:
            return "Aucun objectif compteur"
        }
    }

    private var detail: String {
        let prefix: String? = switch outcome.kind {
        case .task(let item): item.dueDate.map { VoiceCaptureView.dayAndTime(for: $0) }
        case .sessionStarted(let session): "depuis \(session.startedAt.formatted(Self.timeStyle))"
        case .sessionLogged(let sessions): sessions.first.map(TimeFormat.range)
        case .pendingSession(let pending):
            pending.end.map { "\(pending.start.formatted(Self.timeStyle)) – \($0.formatted(Self.timeStyle))" }
        case .goalProgress(let goal), .goalUndone(let goal): GoalMath.valueLabel(goal, sessions: [], now: .now)
        case .sessionStopped, .goalChoice, .goalNotFound: nil
        }
        guard let prefix else { return outcome.transcript }
        return "\(prefix) · \(outcome.transcript)"
    }

    private var symbol: (name: String, color: Color) {
        if outcome.asksForSpace { return ("questionmark.circle.fill", .white) }
        switch outcome.kind {
        case .goalChoice: return ("questionmark.circle.fill", .white)
        case .goalNotFound, .goalUndone: return ("info.circle.fill", .white)
        case .goalProgress: return ("plus.circle.fill", Palette.green)
        case .sessionStarted: return ("play.circle.fill", Palette.green)
        case .sessionStopped(let session): return session == nil ? ("info.circle.fill", .white) : ("stop.circle.fill", Palette.red)
        default: return ("checkmark.circle.fill", Palette.green)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol.name)
                    .font(.system(size: 20))
                    .foregroundStyle(symbol.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if outcome.canUndo {
                    Button("Annuler", action: onUndo)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(.white.opacity(0.16), in: .capsule)
                        .buttonStyle(.plain)
                } else if outcome.canChangeSpace {
                    Button("Changer", action: onChange)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(.white.opacity(0.16), in: .capsule)
                        .buttonStyle(.plain)
                }
            }
            if case .goalChoice(let goals) = outcome.kind {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(goals) { goal in
                            chip(goal.title, color: goal.space?.color) { onPickGoal(goal) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if outcome.asksForSpace {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(outcome.proposals) { space in
                            chip(space.name, color: space.color) { onPick(space) }
                        }
                        if outcome.allowsNone {
                            chip("Aucun", color: nil) { onPick(nil) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Palette.text, in: .rect(cornerRadius: 26))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }

    private func chip(_ title: String, color: Color?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color {
                    Circle().fill(color).frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(.white.opacity(0.16), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
