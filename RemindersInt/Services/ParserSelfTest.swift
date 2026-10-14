#if DEBUG
import Foundation
import SwiftData

/// Runs fixed sentences through the parser and prints phrase → intent / space / confidence / engine.
/// Launched with `-parserSelfTest YES`; read the output with `simctl launch --console`.
enum ParserSelfTest {
    static let phrases = [
        "Rappelle-moi d'appeler Karim demain à 10h",
        "Il faut que je finisse le DM de maths pour vendredi",
        "Dossier de corporate finance à rendre jeudi",
        "Séance de muscu ce soir à 19h",
        "Relancer le client Dupont pour le devis",
        "Faire un TOEIC blanc samedi matin",
        "Préparer la démo Mawiid pour lundi",
        "Envoyer la facture à la fin du mois",
        "Réviser pour la séance de jeudi",
        "Aller à la salle puis réviser les maths",
        "Il faut que j'envoie le devis au client",
        "Il faut que je rende le rapport de stage vendredi",
        "Je commence le sport",
        "Je me mets sur la finance",
        "J'arrête",
        "J'ai fait 2h de maths ce matin",
        "Hier soir j'ai bossé 45 min sur le produit",
        "J'ai signé un club",
        "Séance faite",
        "Un de plus",
        "Encore un test blanc de fait",
    ]

    @MainActor
    static func run(spaces: [SpaceRef]) async {
        var lines = ["PARSER SELF-TEST (\(spaces.count) espaces)", "phrase | intention | espace | confiance | moteur | candidats"]
        for phrase in phrases {
            let parsed = await ParserService.shared.parse(phrase, spaces: spaces)
            let space = parsed.space?.displayPath ?? "nil → « Dans quel espace ? »"
            let candidates = parsed.spaceGuesses.map { "\($0.space.displayPath) \(String(format: "%.2f", $0.confidence))" }.joined(separator: ", ")
            let engine = parsed.engine == .foundationModels ? "Foundation Models" : "secours"
            var due = parsed.dueDate.map { $0.formatted(.dateTime.weekday(.abbreviated).day().hour().minute().locale(.app)) } ?? "sans date"
            if let duration = parsed.duration { due += ", durée \(TimeFormat.short(duration))" }
            lines.append("\(phrase) | \(parsed.intent.rawValue) (\(parsed.title), \(due)) | \(space) | \(String(format: "%.2f", parsed.spaceConfidence)) | \(engine) | \(candidates)")
        }
        // Midnight split: 22:30 → 01:15 the next day gives two pieces.
        let calendar = Calendar.app
        let evening = calendar.date(bySettingHour: 22, minute: 30, second: 0, of: .now) ?? .now
        let pieces = SessionSplit.pieces(from: evening, to: evening.addingTimeInterval(2 * 3600 + 45 * 60))
        let style = Date.FormatStyle.dateTime.day().hour().minute().locale(.app)
        lines.append("SPLIT " + pieces.map { "\($0.start.formatted(style)) → \($0.end.formatted(style))" }.joined(separator: " | "))
        print(lines.joined(separator: "\n"))
    }

    /// Goal routing on the real store (no +1 applied) and hours over a week across two months.
    @MainActor
    static func goalChecks(in context: ModelContext) {
        var lines = ["GOAL CHECKS"]
        let spaces = Space.activeTree(in: context)
        let goals = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        for phrase in phrases.suffix(4) {
            let parsed = FallbackParser(now: .now, spaces: spaces.map(\.ref)).parse(phrase).capture
            let guessed = parsed.spaceGuesses.compactMap { guess in spaces.first { $0.id == guess.space.id } }
            let candidates = VoiceCaptureView.goalCandidates(text: phrase, guessedSpaces: guessed, goals: goals)
            let result = candidates.count == 1 ? "+1 → \(candidates[0].title)" : "question : \(candidates.map(\.title).joined(separator: ", "))"
            lines.append("\(phrase) | \(parsed.intent.rawValue) | \(result)")
        }
        lines.append(contentsOf: hoursAcrossMonths())
        print(lines.joined(separator: "\n"))
    }

    /// Week of Mon 28 Sept – Sun 4 Oct 2026, with a session over the night of 30 Sept.
    @MainActor
    private static func hoursAcrossMonths() -> [String] {
        guard let container = try? ModelContainer(
            for: TaskItem.self, Space.self, Session.self, Goal.self, GoalStep.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ) else { return ["HOURS: no container"] }
        let context = container.mainContext
        let calendar = Calendar.app
        func date(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? .now
        }
        let studies = Space(name: "Études", colorHex: "#5E5CE6", sfSymbol: "book.fill")
        let maths = Space(name: "Maths", colorHex: "#5E5CE6", sfSymbol: "function", parent: studies)
        context.insert(studies)
        context.insert(maths)
        // 27 Sept (previous week) 1h, 29 Sept 2h, 30 Sept 23:00 → 1 Oct 01:00 (split), 1 Oct 3h, 3 Oct 1h30, 5 Oct (next week) 1h.
        let ranges: [(Space, Date, Date)] = [
            (studies, date(9, 27, 10), date(9, 27, 11)),
            (maths, date(9, 29, 9), date(9, 29, 11)),
            (maths, date(9, 30, 23), date(10, 1, 1)),
            (studies, date(10, 1, 14), date(10, 1, 17)),
            (maths, date(10, 3, 18), date(10, 3, 19, 30)),
            (studies, date(10, 5, 9), date(10, 5, 10)),
        ]
        var sessions: [Session] = []
        for (space, start, end) in ranges {
            for piece in SessionSplit.pieces(from: start, to: end) {
                let session = Session(space: space, startedAt: piece.start, endedAt: piece.end)
                context.insert(session)
                sessions.append(session)
            }
        }
        let weekly = Goal(space: studies, title: "Études 20h", kind: .hours, target: 20, period: .week, createdAt: date(9, 1, 0))
        let monthly = Goal(space: studies, title: "Études mois", kind: .hours, target: 60, period: .month, createdAt: date(9, 1, 0))
        let mathsWeekly = Goal(space: maths, title: "Maths sem.", kind: .hours, target: 5, period: .week, createdAt: date(9, 1, 0))
        [weekly, monthly, mathsWeekly].forEach(context.insert)
        let now = date(10, 4, 20)
        let septEnd = date(9, 30, 23, 59)
        func h(_ value: Double) -> String { TimeFormat.short(value * 3600) }
        return [
            "SPLIT PIECES \(sessions.count) (6 sessions, 1 split → 7)",
            "HOURS week 28/09–04/10 Études = \(h(GoalMath.hours(weekly, sessions: sessions, now: now))) (attendu 8h30)",
            "HOURS week 28/09–04/10 Maths = \(h(GoalMath.hours(mathsWeekly, sessions: sessions, now: now))) (attendu 5h30)",
            "HOURS month octobre (au 5/10 20:00) Études = \(h(GoalMath.hours(monthly, sessions: sessions, now: date(10, 5, 20)))) (attendu 6h30)",
            "HOURS month septembre (au 30/09 23:59) Études = \(h(GoalMath.hours(monthly, sessions: sessions, now: septEnd))) (attendu 4h)",
        ]
    }
}
#endif
