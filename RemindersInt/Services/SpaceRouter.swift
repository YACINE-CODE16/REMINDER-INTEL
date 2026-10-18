import Foundation

/// Kind of item a dictated sentence describes.
nonisolated enum CaptureIntent: String, Sendable, Equatable {
    /// "Rappelle-moi…": follow-up notifications until done.
    case reminder
    /// "Il faut que…", "à rendre…": a to-do, one notification at the due date if any.
    case task
    /// "Je commence le sport": opens a tracking session now.
    case sessionStart
    /// "J'arrête", "stop": closes the open session.
    case sessionStop
    /// "J'ai fait 2h de maths ce matin": records a past session.
    case sessionLog
    /// "Un club de plus", "séance faite": +1 on a counter goal.
    case goalProgress
    /// "J'ai fait dhuhr", "asr en retard", "j'ai rattrapé isha d'hier": ticks a prayer (prayer.check).
    case prayerCheck

    var isSession: Bool { self == .sessionStart || self == .sessionStop || self == .sessionLog }
}

/// A candidate space for a sentence.
nonisolated struct SpaceGuess: Sendable, Equatable {
    var space: SpaceRef
    var confidence: Double
}

/// Rule-based space routing: keyword match on space names and a few synonyms.
nonisolated struct SpaceRouter {
    let spaces: [SpaceRef]

    /// Below this confidence the space is left empty and the user is asked.
    static let threshold = 0.6

    private static let nameWeight = 0.85
    private static let strongWeight = 0.8
    /// Words with another common meaning ("fin" du mois, "séance" de cinéma).
    private static let weakWeight = 0.55
    /// Hits in several branches: none is trusted.
    private static let ambiguousCap = 0.5

    /// Synonyms keyed by normalized space name. Strong first, then weak.
    private static let synonyms: [String: (strong: [String], weak: [String])] = [
        "etudes": (["etude", "cours", "exam", "examen", "partiel", "partiels", "fac", "ecole", "reviser", "revision", "revisions", "dm", "devoir maison"], []),
        "finance": (["finances", "financier", "financiere", "corporate finance", "bourse"], ["fin"]),
        "maths": (["math", "mathematiques", "mathematique", "proba", "probas", "probabilites", "stats", "statistiques", "algebre"], []),
        "tage mage": (["tagemage", "tage"], []),
        "anglais": (["english", "toeic", "toefl", "ielts"], []),
        "fieldz": (["field z"], ["fields"]),
        "produit": (["roadmap", "fonctionnalite", "feature", "maquette", "maquettes"], ["bug"]),
        "commercial": (["client", "clients", "prospect", "prospects", "prospection", "devis", "vente", "ventes"], []),
        "admin": (["administratif", "urssaf", "impots", "facture", "factures", "compta", "comptabilite"], []),
        "mawiid": (["mawid", "mawaid", "mawide"], []),
        "webentis": (["web entis"], []),
        "sport": (["salle", "muscu", "musculation", "running", "footing", "jogging", "gym", "entrainement", "courir"], ["seance"]),
        "perso": (["personnel", "maison", "famille", "courses", "loyer", "medecin"], []),
    ]

    /// Up to 3 guesses, best first; empty when nothing matches.
    func route(_ text: String) -> [SpaceGuess] {
        let haystack = " " + Self.normalize(text) + " "
        var hits: [SpaceGuess] = []
        for space in spaces {
            let key = Self.normalize(space.name)
            let entry = Self.synonyms[key]
            var weight = 0.0
            if Self.matches(key, in: haystack) { weight = Self.nameWeight }
            if weight == 0, entry?.strong.contains(where: { Self.matches($0, in: haystack) }) == true { weight = Self.strongWeight }
            if weight == 0, entry?.weak.contains(where: { Self.matches($0, in: haystack) }) == true { weight = Self.weakWeight }
            if weight > 0 { hits.append(SpaceGuess(space: space, confidence: weight)) }
        }

        // An ancestor hit confirms its descendant ("révision de maths" → Études > Maths).
        let leaves = hits.filter { hit in
            !hits.contains { other in other.space.id != hit.space.id && Self.isAncestor(hit.space, of: other.space) }
        }.map { leaf -> SpaceGuess in
            let confirmed = hits.contains { Self.isAncestor($0.space, of: leaf.space) }
            return SpaceGuess(space: leaf.space, confidence: confirmed ? min(0.95, leaf.confidence + 0.1) : leaf.confidence)
        }

        let ranked = leaves.sorted { $0.confidence > $1.confidence }
        guard ranked.count > 1 else { return ranked }
        return ranked.prefix(3).map { SpaceGuess(space: $0.space, confidence: min($0.confidence, Self.ambiguousCap)) }
    }

    private static func isAncestor(_ ancestor: SpaceRef, of space: SpaceRef) -> Bool {
        space.path.count > ancestor.path.count && Array(space.path.prefix(ancestor.path.count)) == ancestor.path
    }

    /// Whole-word match, plural "s" tolerated.
    private static func matches(_ keyword: String, in haystack: String) -> Bool {
        haystack.contains(" \(keyword) ") || haystack.contains(" \(keyword)s ")
    }

    /// Lowercase, no accents, punctuation and apostrophes as spaces.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
