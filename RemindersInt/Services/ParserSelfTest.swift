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
    ]

    @MainActor
    static func run(spaces: [SpaceRef]) async {
        var lines = ["PARSER SELF-TEST (\(spaces.count) espaces)", "phrase | intention | espace | confiance | moteur | candidats"]
        for phrase in phrases {
            let parsed = await ParserService.shared.parse(phrase, spaces: spaces)
            let space = parsed.space?.displayPath ?? "nil → « Dans quel espace ? »"
            let candidates = parsed.spaceGuesses.map { "\($0.space.displayPath) \(String(format: "%.2f", $0.confidence))" }.joined(separator: ", ")
            let engine = parsed.engine == .foundationModels ? "Foundation Models" : "secours"
            let due = parsed.dueDate.map { $0.formatted(.dateTime.weekday(.abbreviated).day().hour().minute().locale(.app)) } ?? "sans date"
            lines.append("\(phrase) | \(parsed.intent.rawValue) (\(parsed.title), \(due)) | \(space) | \(String(format: "%.2f", parsed.spaceConfidence)) | \(engine) | \(candidates)")
        }
        print(lines.joined(separator: "\n"))
    }
}
#endif
