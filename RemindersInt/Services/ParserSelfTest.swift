#if DEBUG
import Foundation

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
}
#endif
