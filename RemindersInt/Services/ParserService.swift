import Foundation
import FoundationModels
import Observation

/// Result of parsing a dictated sentence.
nonisolated struct ParsedReminder: Sendable, Equatable {
    enum Engine: Sendable {
        case foundationModels
        case fallback
    }

    var title: String
    /// nil when the sentence expresses no date: the user is asked instead of guessing.
    var dueDate: Date?
    /// nil when the sentence does not ask for a repeat: the default from Settings applies.
    var repeatInterval: RepeatInterval?
    var confidence: Double
    var engine: Engine
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

/// Text -> ParsedReminder, on-device only. Uses Foundation Models when Apple Intelligence is
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

    func parse(_ text: String, now: Date = .now) async -> ParsedReminder {
        let fallback = FallbackParser(now: now).parse(text)
        guard isModelAvailable else { return fallback.reminder }
        do {
            let session = LanguageModelSession(instructions: Self.instructions(now: now))
            let response = try await session.respond(
                to: text,
                generating: GeneratedReminder.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return Self.merge(response.content, fallback: fallback)
        } catch {
            // Degrade to the rule-based parser for this sentence.
            recordFailure(error)
            return fallback.reminder
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
    private static func merge(_ generated: GeneratedReminder, fallback: FallbackParser.Output) -> ParsedReminder {
        let title = generated.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelDate = Self.date(from: generated.dueDate)
        let dueDate = fallback.isRelativeOffset ? fallback.reminder.dueDate : (modelDate ?? fallback.reminder.dueDate)
        return ParsedReminder(
            title: title.isEmpty ? fallback.reminder.title : title,
            dueDate: dueDate,
            repeatInterval: generated.repeatInterval.repeatInterval ?? fallback.reminder.repeatInterval,
            confidence: min(max(generated.confidence, 0), 1),
            engine: .foundationModels
        )
    }

    private static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.paris.timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: string.trimmingCharacters(in: .whitespaces))
    }

    static func instructions(now: Date) -> String {
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

        return """
        Tu extrais un rappel d'une phrase dictée en français. Réponds uniquement avec les champs demandés.
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
        """
    }
}

// MARK: - Foundation Models schema

// Date is not a Generable type: the model writes an ISO string that is parsed afterwards.
@Generable
nonisolated struct GeneratedReminder {
    @Guide(description: "L'action à faire, courte, sans « rappelle-moi de », sans date ni relance")
    var title: String

    @Guide(description: "Date et heure absolues au format AAAA-MM-JJTHH:MM (heure de Paris), ou chaîne vide si la phrase n'exprime ni date ni heure")
    var dueDate: String

    @Guide(description: "Intervalle de relance demandé dans la phrase, unspecified sinon")
    var repeatInterval: GeneratedRepeatInterval

    @Guide(description: "Confiance dans l'extraction, entre 0 et 1", .range(0.0...1.0))
    var confidence: Double
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
