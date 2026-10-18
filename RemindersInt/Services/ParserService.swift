import Foundation
import FoundationModels
import Observation

/// Result of parsing a dictated sentence.
nonisolated struct ParsedCapture: Sendable, Equatable {
    enum Engine: Sendable {
        case foundationModels
        case fallback
    }

    var intent: CaptureIntent
    var title: String
    /// nil when the sentence expresses no date: a reminder then asks the user instead of guessing.
    var dueDate: Date?
    /// nil when the sentence does not ask for a repeat: the default from Settings applies.
    var repeatInterval: RepeatInterval?
    /// Length of a past session (sessionLog).
    var duration: TimeInterval? = nil
    /// Which prayer and how (prayerCheck).
    var prayerCheck: PrayerCheck? = nil
    var confidence: Double
    /// Most likely spaces, best first; empty when nothing fits.
    var spaceGuesses: [SpaceGuess]
    var engine: Engine

    /// The space to file the item in, only when the best guess clears the threshold.
    var space: SpaceRef? {
        guard let best = spaceGuesses.first, best.confidence >= SpaceRouter.threshold else { return nil }
        return best.space
    }

    var spaceConfidence: Double { spaceGuesses.first?.confidence ?? 0 }
}

/// A dictated prayer tick: "j'ai fait dhuhr", "asr en retard", "j'ai rattrapé isha d'hier".
nonisolated struct PrayerCheck: Sendable, Equatable {
    enum Mark: Sendable {
        /// On time or late, from the clock.
        case done
        case onTime
        case late
        case madeUp
    }

    var prayer: Prayer
    var mark: Mark
    /// "d'hier", "hier".
    var isYesterday: Bool
}

extension Calendar {
    /// Reference calendar for parsing: Europe/Paris, French.
    nonisolated static let paris: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fr_FR")
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        calendar.firstWeekday = 2
        return calendar
    }()
}

/// Text -> ParsedCapture (intent, title, date, repeat, space), on-device only. Uses Foundation Models when Apple Intelligence is
/// available, otherwise a small rule-based French parser. Never calls a cloud API.
@Observable
final class ParserService {
    static let shared = ParserService()

    /// Set when generation fails although the model reports available, e.g. a simulator
    /// whose host Mac has Apple Intelligence off (the model assets are missing).
    private(set) var generationFailed = false

    /// Availability is read on each access: Apple Intelligence can be toggled while the app runs.
    var isModelAvailable: Bool {
        SystemLanguageModel.default.isAvailable && !generationFailed
    }

    /// Startup check: a one-token generation proves the model actually runs (and prewarms it).
    func checkModel() async {
        guard isModelAvailable else { return }
        do {
            _ = try await LanguageModelSession().respond(to: "OK", options: GenerationOptions(maximumResponseTokens: 1))
        } catch {
            recordFailure(error)
        }
    }

    func parse(_ text: String, spaces: [SpaceRef] = [], now: Date = .now) async -> ParsedCapture {
        let fallback = FallbackParser(now: now, spaces: spaces).parse(text)
        guard isModelAvailable else { return fallback.capture }
        do {
            let session = LanguageModelSession(instructions: Self.instructions(now: now, spaces: spaces))
            let response = try await session.respond(
                to: text,
                generating: GeneratedCapture.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return Self.merge(response.content, fallback: fallback, spaces: spaces)
        } catch {
            // Degrade to the rule-based parser for this sentence.
            recordFailure(error)
            return fallback.capture
        }
    }

    /// Errors tied to one sentence keep the model on; anything else switches to simplified mode.
    private func recordFailure(_ error: any Error) {
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .guardrailViolation, .exceededContextWindowSize:
                return
            default:
                break
            }
        }
        generationFailed = true
    }

    /// Model output first; deterministic arithmetic wins for "dans X minutes", and the
    /// rule-based date fills in when the model returns none.
    /// Space paths the model returns are matched back to real spaces; unknown ones are dropped,
    /// and the keyword guesses are used when the model returns none.
    private static func merge(_ generated: GeneratedCapture, fallback: FallbackParser.Output, spaces: [SpaceRef]) -> ParsedCapture {
        let base = fallback.capture
        // Prayer names are unambiguous: the rule-based reading wins, the model fills a gap.
        if generated.intent == .prayerCheck || base.intent == .prayerCheck {
            let rules = base.prayerCheck
            guard let prayer = rules?.prayer ?? generated.prayer.prayer else { return base }
            var mark = rules?.mark ?? generated.prayerMark.mark
            if mark == .done, generated.prayerMark.mark != .done { mark = generated.prayerMark.mark }
            let check = PrayerCheck(prayer: prayer, mark: mark, isYesterday: (rules?.isYesterday ?? false) || generated.prayerYesterday)
            return ParsedCapture(intent: .prayerCheck, title: prayer.name, dueDate: nil, repeatInterval: nil, prayerCheck: check, confidence: generated.confidence, spaceGuesses: [], engine: .foundationModels)
        }
        let title = generated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelDate = Self.date(from: generated.dueDate)
        let dueDate = fallback.isRelativeOffset ? base.dueDate : (modelDate ?? base.dueDate)
        var guesses: [SpaceGuess] = []
        for guess in generated.spaces {
            guard let space = Self.space(matching: guess.path, in: spaces), !guesses.contains(where: { $0.space.id == space.id }) else { continue }
            guesses.append(SpaceGuess(space: space, confidence: min(max(guess.confidence, 0), 1)))
        }
        guesses.sort { $0.confidence > $1.confidence }
        let duration = generated.durationMinutes > 0 ? TimeInterval(generated.durationMinutes * 60) : base.duration
        var intent = generated.intent.intent
        // A past session needs a length; without one it is a plain task.
        if intent == .sessionLog, duration == nil { intent = .task }
        return ParsedCapture(
            intent: intent,
            title: title.isEmpty ? base.title : title,
            dueDate: intent == .sessionStart || intent == .sessionStop ? nil : dueDate,
            repeatInterval: generated.repeatInterval.repeatInterval ?? base.repeatInterval,
            duration: intent == .sessionLog ? duration : nil,
            confidence: min(max(generated.confidence, 0), 1),
            spaceGuesses: guesses.isEmpty ? base.spaceGuesses : Array(guesses.prefix(3)),
            engine: .foundationModels
        )
    }

    /// Exact path first ("Études > Finance"), then a unique last component ("Finance").
    private static func space(matching path: String, in spaces: [SpaceRef]) -> SpaceRef? {
        let key = SpaceRouter.normalize(path)
        guard !key.isEmpty else { return nil }
        if let exact = spaces.first(where: { SpaceRouter.normalize($0.modelPath) == key }) { return exact }
        let byName = spaces.filter { SpaceRouter.normalize($0.name) == key }
        return byName.count == 1 ? byName[0] : nil
    }

    private static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.paris.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: string.trimmingCharacters(in: .whitespaces))
    }

    static func instructions(now: Date, spaces: [SpaceRef] = []) -> String {
        let calendar = Calendar.paris
        let dayFormat = Date.FormatStyle(date: .complete, time: .omitted, locale: calendar.locale ?? .app, calendar: calendar, timeZone: calendar.timeZone)
        let isoDay = Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day()
        let time = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: calendar.locale ?? .app, calendar: calendar, timeZone: calendar.timeZone))
        // A day table spares the model weekday arithmetic.
        let days = (0...7).compactMap { offset -> String? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { return nil }
            let label = switch offset {
            case 0: "aujourd'hui"
            case 1: "demain"
            case 2: "après-demain"
            default: day.formatted(.dateTime.weekday(.wide).locale(calendar.locale ?? .app))
            }
            return "- \(label) : \(day.formatted(dayFormat)) = \(day.formatted(isoDay))"
        }.joined(separator: "\n")
        let spaceList = spaces.isEmpty ? "(aucun)" : spaces.map { "- \($0.modelPath)" }.joined(separator: "\n")

        return """
        Tu analyses une phrase dictée en français pour créer un rappel ou une tâche. Réponds uniquement avec les champs demandés.
        Maintenant : \(now.formatted(dayFormat)), \(time), heure de Paris.
        Jours de référence :
        \(days)

        Règles :
        - title : l'action à faire, courte, sans « rappelle-moi de », « n'oublie pas de », sans la date, l'heure ni la relance. Commence par une majuscule. Garde les noms propres.
        - dueDate : date et heure absolues au format AAAA-MM-JJTHH:MM.
          « dans 30 minutes » = maintenant plus 30 minutes. « matin » = 09:00, « midi » = 12:00, « après-midi » = 15:00, « ce soir » ou « soir » = 19:00.
          Un jour sans heure = 09:00 ce jour-là. Une heure sans jour = aujourd'hui si elle n'est pas passée, sinon demain.
          « jeudi » ou « jeudi prochain » = le prochain jeudi après aujourd'hui, d'après la table.
          Si la phrase n'exprime aucune date ni heure, dueDate est une chaîne vide. N'invente jamais de date.
        - repeatInterval : seulement si la phrase demande une relance (« toutes les 5 minutes », « toutes les heures »…), sinon unspecified.
        - confidence : ta confiance dans l'extraction, entre 0 et 1.
        - intent : reminder pour un rappel à heure précise avec relances (« rappelle-moi », « n'oublie pas de me », une relance demandée, un appel à une heure donnée).
          task pour une chose à faire (« il faut que », « je dois », « à rendre », un devoir, « relancer quelqu'un », préparer, finir, réviser), souvent sans heure précise.
          sessionStart quand on commence une activité maintenant (« je commence le sport », « je me mets sur la finance », « c'est parti pour les maths »).
          sessionStop quand on arrête l'activité en cours (« j'arrête », « stop », « fini », « je fais une pause »).
          sessionLog quand on raconte un temps déjà passé avec une durée (« j'ai fait 2h de maths ce matin », « hier j'ai bossé 45 min sur FieldZ »).
          goalProgress quand on annonce une unité de plus vers un objectif compteur (« j'ai signé un club », « séance faite », « un de plus », « encore un test blanc »).
          prayerCheck quand on coche une prière (« j'ai fait dhuhr », « fajr fait », « asr en retard », « j'ai rattrapé isha d'hier »). Noms acceptés : fajr ou sobh, dhuhr ou dohr, asr, maghrib, isha ou icha.
        - prayer : pour prayerCheck, la prière (fajr, dhuhr, asr, maghrib, isha) ; none sinon.
        - prayerMark : done si la prière est simplement faite, onTime si « à l'heure » est dit, late si « en retard », madeUp si « rattrapé ».
        - prayerYesterday : true si la prière est celle d'hier (« d'hier », « hier »).
        - durationMinutes : pour sessionLog, la durée en minutes (« 2h » = 120, « 1h30 » = 90) ; 0 sinon.
          Pour sessionLog, dueDate est le début de la session si un moment est donné (« ce matin » = 09:00, « hier soir » = 19:00 la veille), sinon chaîne vide. Pour sessionStart et sessionStop, dueDate est une chaîne vide.
        - spaces : jusqu'à 3 espaces les plus probables parmi la liste ci-dessous, du plus probable au moins probable.
          Recopie le chemin exactement tel qu'il est écrit. Donne pour chacun une confiance entre 0 et 1.
          Préfère le sous-espace le plus précis. Si aucun espace ne correspond clairement, renvoie une liste vide.
        Espaces :
        \(spaceList)
        """
    }
}

// MARK: - Foundation Models schema

// Date is not a Generable type: the model writes an ISO string that is parsed afterwards.
@Generable
nonisolated struct GeneratedCapture {
    @Guide(description: "reminder pour un rappel avec relances, task pour une chose à faire, sessionStart / sessionStop / sessionLog pour le suivi du temps, goalProgress pour +1 sur un objectif")
    var intent: GeneratedIntent

    @Guide(description: "L'action à faire, courte, sans « rappelle-moi de » ni « il faut que je », sans date ni relance")
    var title: String

    @Guide(description: "Date et heure absolues au format AAAA-MM-JJTHH:MM (heure de Paris), ou chaîne vide si la phrase n'exprime ni date ni heure")
    var dueDate: String

    @Guide(description: "Intervalle de relance demandé dans la phrase, unspecified sinon")
    var repeatInterval: GeneratedRepeatInterval

    @Guide(description: "Pour sessionLog, durée de la session passée en minutes ; 0 sinon", .range(0...1440))
    var durationMinutes: Int

    @Guide(description: "Confiance dans l'extraction, entre 0 et 1", .range(0.0...1.0))
    var confidence: Double

    @Guide(description: "Jusqu'à 3 espaces probables, chemin recopié de la liste, du plus probable au moins probable", .maximumCount(3))
    var spaces: [GeneratedSpaceGuess]

    @Guide(description: "Pour prayerCheck, la prière cochée ; none sinon")
    var prayer: GeneratedPrayer

    @Guide(description: "Pour prayerCheck : done, onTime (« à l'heure »), late (« en retard ») ou madeUp (« rattrapé »)")
    var prayerMark: GeneratedPrayerMark

    @Guide(description: "Pour prayerCheck, true si c'est la prière d'hier")
    var prayerYesterday: Bool
}

@Generable
nonisolated enum GeneratedPrayer {
    case none
    case fajr
    case dhuhr
    case asr
    case maghrib
    case isha

    var prayer: Prayer? {
        switch self {
        case .none: nil
        case .fajr: .fajr
        case .dhuhr: .dhuhr
        case .asr: .asr
        case .maghrib: .maghrib
        case .isha: .isha
        }
    }
}

@Generable
nonisolated enum GeneratedPrayerMark {
    case done
    case onTime
    case late
    case madeUp

    var mark: PrayerCheck.Mark {
        switch self {
        case .done: .done
        case .onTime: .onTime
        case .late: .late
        case .madeUp: .madeUp
        }
    }
}

@Generable
nonisolated struct GeneratedSpaceGuess {
    @Guide(description: "Chemin exact de l'espace, par exemple « Études > Finance »")
    var path: String

    @Guide(description: "Confiance que la phrase appartient à cet espace, entre 0 et 1", .range(0.0...1.0))
    var confidence: Double
}

@Generable
nonisolated enum GeneratedIntent {
    case reminder
    case task
    case sessionStart
    case sessionStop
    case sessionLog
    case goalProgress
    case prayerCheck

    var intent: CaptureIntent {
        switch self {
        case .reminder: .reminder
        case .task: .task
        case .sessionStart: .sessionStart
        case .sessionStop: .sessionStop
        case .sessionLog: .sessionLog
        case .goalProgress: .goalProgress
        case .prayerCheck: .prayerCheck
        }
    }
}

@Generable
nonisolated enum GeneratedRepeatInterval {
    case unspecified
    case noRepeat
    case every5min
    case every15min
    case every30min
    case hourly

    var repeatInterval: RepeatInterval? {
        switch self {
        case .unspecified: nil
        case .noRepeat: RepeatInterval.none
        case .every5min: .every5min
        case .every15min: .every15min
        case .every30min: .every30min
        case .hourly: .hourly
        }
    }
}
