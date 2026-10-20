import Foundation

/// Minimal rule-based French parser, used when Apple Intelligence is unavailable.
/// Handles "dans X min/heures", "aujourd'hui / demain / après-demain / lundi…",
/// "ce matin / ce soir", "à 16h30 / à midi" and "toutes les X minutes / heures",
/// plus keyword-based intent and space routing.
nonisolated struct FallbackParser {
    struct Output {
        var capture: ParsedCapture
        /// True for "dans X minutes" style dates, computed exactly from now.
        var isRelativeOffset: Bool
    }

    let now: Date
    var spaces: [SpaceRef] = []
    var gym: GymContext = .empty
    var calendar: Calendar = .paris

    private static let reminderMarkers = #"rappelle[- ]?moi|n['’]oublie pas|fais[- ]moi penser|relance[- ]moi|\brappel\b"#
    private static let taskMarkers = #"il faut que|il faudrait|faut que je|je dois|[àa] rendre|\bdevoirs?\b|\brelancer\b|[àa] faire|\bfinir\b|\bterminer\b|\bpr[ée]parer\b|\br[ée]viser\b"#

    private static let numbers: [String: Int] = [
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7,
        "huit": 8, "neuf": 9, "dix": 10, "onze": 11, "douze": 12, "quinze": 15, "vingt": 20,
        "trente": 30, "quarante": 40, "quarante-cinq": 45,
    ]
    private static let numberPattern = #"(\d+|une?|deux|trois|quatre|cinq|six|sept|huit|neuf|dix|onze|douze|quinze|vingt|trente|quarante-cinq|quarante)"#
    private static let weekdays = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]

    func parse(_ text: String) -> Output {
        if let check = Self.prayerCheck(in: text) {
            let capture = ParsedCapture(intent: .prayerCheck, title: check.prayer.name, dueDate: nil, repeatInterval: nil, prayerCheck: check, confidence: 0.8, spaceGuesses: [], engine: .fallback)
            return Output(capture: capture, isRelativeOffset: false)
        }
        if let (intent, command) = GymParsing.command(in: text, context: gym) {
            let capture = ParsedCapture(intent: intent, title: text, dueDate: nil, repeatInterval: nil, gym: command, confidence: 0.8, spaceGuesses: [], engine: .fallback)
            return Output(capture: capture, isRelativeOffset: false)
        }
        var rest = text
        // Session sentences first: "j'ai fait 2h" must not be read as 02:00.
        var sessionIntent = Self.sessionIntent(of: text)
        var duration: TimeInterval?
        if sessionIntent == .sessionLog {
            duration = Self.takeDuration(from: &rest)
            if duration == nil { sessionIntent = nil }
        }
        var minutesOffset: Int?
        var dayOffset: Int?
        var hour: Int?
        var minute: Int?
        var partOfDayHour: Int?
        var repeatInterval: RepeatInterval?

        // Repeat.
        if let match = Self.take(#"(?:,?\s*et\s+)?(?:relance[- ]moi\s+)?toutes les\s+"# + Self.numberPattern + #"\s*(?:minutes?|min)\b"#, from: &rest) {
            repeatInterval = Self.repeatInterval(minutes: Self.number(match[1]))
        } else if Self.take(#"(?:,?\s*et\s+)?(?:relance[- ]moi\s+)?toutes les\s+demi-heures?"#, from: &rest) != nil {
            repeatInterval = .every30min
        } else if Self.take(#"(?:,?\s*et\s+)?(?:relance[- ]moi\s+)?(?:toutes les heures|chaque heure|toutes les 1\s*h)"#, from: &rest) != nil {
            repeatInterval = .hourly
        } else if Self.take(#",?\s*(?:sans|pas de)\s+relances?"#, from: &rest) != nil {
            repeatInterval = RepeatInterval.none
        }

        // Relative offset.
        if let match = Self.take(#"dans\s+(\d+)\s*h\s*(\d{2})\b"#, from: &rest) {
            minutesOffset = (Self.number(match[1]) ?? 0) * 60 + (Self.number(match[2]) ?? 0)
        } else if Self.take(#"dans\s+une\s+demi-heure"#, from: &rest) != nil {
            minutesOffset = 30
        } else if Self.take(#"dans\s+un\s+quart\s+d['’]heure"#, from: &rest) != nil {
            minutesOffset = 15
        } else if let match = Self.take(#"dans\s+"# + Self.numberPattern + #"\s*(minutes?|min|heures?|h)\b"#, from: &rest),
                  let value = Self.number(match[1]) {
            minutesOffset = match[2].hasPrefix("m") ? value : value * 60
        }

        // Day.
        if Self.take(#"après-demain"#, from: &rest) != nil {
            dayOffset = 2
        } else if Self.take(#"avant-hier"#, from: &rest) != nil {
            dayOffset = -2
        } else if Self.take(#"hier"#, from: &rest) != nil {
            dayOffset = -1
        } else if Self.take(#"demain"#, from: &rest) != nil {
            dayOffset = 1
        } else if Self.take(#"aujourd['’]hui"#, from: &rest) != nil {
            dayOffset = 0
        } else if let match = Self.take(#"(?:ce\s+)?(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)(?:\s+prochain)?"#, from: &rest),
                  let target = Self.weekdays.firstIndex(of: match[1].lowercased()) {
            let today = calendar.component(.weekday, from: now) - 1
            let diff = (target - today + 7) % 7
            dayOffset = diff == 0 ? 7 : diff
        }

        // Part of day.
        if Self.take(#"(?:ce|le|du|au)?\s*matin"#, from: &rest) != nil {
            partOfDayHour = 9
        } else if Self.take(#"(?:cet|l['’])?\s*après-midi"#, from: &rest) != nil {
            partOfDayHour = 15
        } else if Self.take(#"(?:ce|le|du|au)?\s*soir"#, from: &rest) != nil {
            partOfDayHour = 19
        }
        if partOfDayHour != nil, dayOffset == nil { dayOffset = 0 }

        // Time.
        if Self.take(#"(?:à|a|vers)?\s*midi"#, from: &rest) != nil {
            hour = 12
            minute = 0
        } else if Self.take(#"(?:à|a|vers)?\s*minuit"#, from: &rest) != nil {
            hour = 0
            minute = 0
            if dayOffset == nil { dayOffset = 1 }
        } else if let match = Self.take(#"(?:à|a|vers)?\s*(\d{1,2})\s*(?:h|heures?|:)\s*(\d{2})?\b"#, from: &rest),
                  let value = Self.number(match[1]), value < 24 {
            hour = value
            minute = match[2].isEmpty ? 0 : Self.number(match[2])
            // "8h du soir" / "3h de l'après-midi".
            if let partOfDayHour, partOfDayHour >= 15, value < 12 { hour = value + 12 }
        }

        let dueDate = resolveDate(
            minutesOffset: minutesOffset,
            dayOffset: dayOffset,
            hour: hour ?? partOfDayHour,
            minute: minute,
            preferPast: sessionIntent == .sessionLog
        )
        // "Je commence le DM demain" plans something: not a session starting now.
        if sessionIntent == .sessionStart, dueDate != nil { sessionIntent = nil }
        let progress: CaptureIntent? = sessionIntent == nil && dueDate == nil && Self.isGoalProgress(text) ? .goalProgress : nil
        let intent = sessionIntent ?? progress ?? Self.intent(
            of: text,
            hasRepeat: repeatInterval != nil,
            hasExplicitTime: hour != nil || minutesOffset != nil
        )
        let capture = ParsedCapture(
            intent: intent,
            title: Self.cleanTitle(rest),
            dueDate: intent == .sessionStart || intent == .sessionStop || intent == .goalProgress ? nil : dueDate,
            repeatInterval: intent.isSession || intent == .goalProgress ? nil : repeatInterval,
            duration: duration,
            confidence: dueDate == nil ? 0.3 : 0.6,
            spaceGuesses: SpaceRouter(spaces: spaces).route(text),
            engine: .fallback
        )
        return Output(capture: capture, isRelativeOffset: minutesOffset != nil)
    }

    // MARK: - Prayers

    private static let prayerNames: [(Prayer, String)] = [
        (.fajr, #"fajr|fadjr|fajar|sobh|sobhi|subh|sobeh"#),
        (.dhuhr, #"dhuhr|dhohr|dohr|dhor|duhr|zohr|zuhr|jumu['’]?a|joumou['’]?a"#),
        (.asr, #"asr|asser|aser"#),
        (.maghrib, #"maghrib|maghreb|magrib"#),
        (.isha, #"isha|icha|ichaa|ishaa"#),
    ]
    private static let prayerDoneMarkers = #"\bfaite?s?\b|\bpri[ée]e?\b|\baccompli|\bvalid[ée]|\bok\b|[àa] l['’]heure|en retard|rattrap"#

    /// "J'ai fait dhuhr", "fajr fait", "asr en retard", "j'ai rattrapé isha d'hier".
    /// Needs a prayer name and a tick word; "rappelle-moi…" stays a reminder.
    static func prayerCheck(in text: String) -> PrayerCheck? {
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        guard text.range(of: prayerDoneMarkers, options: options) != nil,
              text.range(of: reminderMarkers, options: options) == nil,
              let prayer = prayerNames.first(where: { text.range(of: #"(?<![\p{L}])(?:"# + $0.1 + #")(?![\p{L}])"#, options: options) != nil })?.0
        else { return nil }
        let mark: PrayerCheck.Mark
        if text.range(of: "rattrap", options: options) != nil {
            mark = .madeUp
        } else if text.range(of: "en retard", options: options) != nil {
            mark = .late
        } else if text.range(of: #"[àa] l['’]heure"#, options: options) != nil {
            mark = .onTime
        } else {
            mark = .done
        }
        let isYesterday = text.range(of: #"\bhier\b"#, options: options) != nil
        return PrayerCheck(prayer: prayer, mark: mark, isYesterday: isYesterday)
    }

    private static let startMarkers = #"\bje commence\b|\bje me mets\b|\bje m['’]y mets\b|\bje d[ée]marre\b|\bc['’]est parti\b|\bje m['’]attaque\b|\bje lance (?:une|la|le) (?:session|chrono)"#
    private static let stopMarkers = #"^\s*(?:stop|j['’]arr[êe]te|je m['’]arr[êe]te|j['’]ai fini|j['’]ai termin[ée]|fini|termin[ée]|c['’]est fini|fin de (?:la )?session|je fais une pause|pause)\b"#
    private static let logMarkers = #"\bj['’]ai\s+(?:fait|bossé|bosse|travaillé|révisé|étudié|passé|couru|joué|lu|codé)\b"#

    private static let progressMarkers = #"\bune? (?:\p{L}+ )?de plus\b|\bencore une?\b|\bj['’]ai sign[ée]\b|\bs[ée]ance faite\b|\bplus une?\b|\+ ?1\b"#

    /// "Un club de plus", "séance faite", "j'ai signé un club", "encore un".
    static func isGoalProgress(_ text: String) -> Bool {
        text.range(of: progressMarkers, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Session sentences: start / stop / past log. Nil for anything else.
    static func sessionIntent(of text: String) -> CaptureIntent? {
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        if text.range(of: logMarkers, options: options) != nil, durationMatch(in: text) != nil {
            return .sessionLog
        }
        if text.range(of: stopMarkers, options: options) != nil {
            // "J'ai fini le DM de maths" is a task update, not the end of a session.
            let words = text.split(whereSeparator: { $0.isWhitespace }).count
            if words <= 4 || text.range(of: #"session|chrono"#, options: options) != nil {
                return .sessionStop
            }
        }
        if text.range(of: startMarkers, options: options) != nil {
            return .sessionStart
        }
        return nil
    }

    private static let durationPattern = #"(?:(\d+)\s*h(?:eures?)?\s*(\d{1,2})?(?!\d)(?:\s*min(?:utes?)?)?|(\d+)\s*(?:min|minutes?)\b|(une|deux|trois|quatre|cinq|six)\s+heures?(\s+et\s+demie)?|une\s+demi-heure|trois\s+quarts\s+d['’]heure|un\s+quart\s+d['’]heure)"#

    private static func durationMatch(in text: String) -> Range<String.Index>? {
        text.range(of: durationPattern, options: [.regularExpression, .caseInsensitive])
    }

    /// Removes the first duration ("2h", "1h30", "45 min", "une heure et demie") and returns it.
    static func takeDuration(from text: inout String) -> TimeInterval? {
        guard let match = take(durationPattern, from: &text) else { return nil }
        let whole = match[0].lowercased()
        if whole.contains("demi-heure") { return 30 * 60 }
        if whole.contains("trois quarts") { return 45 * 60 }
        if whole.contains("quart") { return 15 * 60 }
        if let hours = number(match[1]) {
            return TimeInterval(hours * 3600 + (number(match[2]) ?? 0) * 60)
        }
        if let minutes = number(match[3]) {
            return TimeInterval(minutes * 60)
        }
        if let hours = number(match[4]) {
            return TimeInterval(hours * 3600 + (match[5].isEmpty ? 0 : 1800))
        }
        return nil
    }

    /// "Rappelle-moi" or a repeat → reminder; "il faut que", "à rendre", "relancer"… → task;
    /// otherwise a precise time means a reminder, anything else a task.
    static func intent(of text: String, hasRepeat: Bool, hasExplicitTime: Bool) -> CaptureIntent {
        if text.range(of: reminderMarkers, options: [.regularExpression, .caseInsensitive]) != nil || hasRepeat {
            return .reminder
        }
        if text.range(of: taskMarkers, options: [.regularExpression, .caseInsensitive]) != nil {
            return .task
        }
        return hasExplicitTime ? .reminder : .task
    }

    /// `preferPast`: for a past session, a bare time later than now means yesterday, not tomorrow.
    private func resolveDate(minutesOffset: Int?, dayOffset: Int?, hour: Int?, minute: Int?, preferPast: Bool = false) -> Date? {
        if let minutesOffset {
            return calendar.date(byAdding: .minute, value: minutesOffset, to: now)
        }
        guard dayOffset != nil || hour != nil else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        guard let day = calendar.date(byAdding: .day, value: dayOffset ?? 0, to: startOfToday),
              let date = calendar.date(bySettingHour: hour ?? 9, minute: minute ?? 0, second: 0, of: day)
        else { return nil }
        if preferPast {
            if dayOffset == nil, date > now {
                return calendar.date(byAdding: .day, value: -1, to: date)
            }
            return date
        }
        // A bare time already passed today means tomorrow.
        if dayOffset == nil, date <= now {
            return calendar.date(byAdding: .day, value: 1, to: date)
        }
        return date
    }

    // MARK: - Helpers

    /// Removes the first case-insensitive match from `text` and returns its capture groups
    /// (index 0 = whole match, empty string for groups that did not participate).
    private static func take(_ pattern: String, from text: inout String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\p{L}\d])"# + pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        let groups = (0..<match.numberOfRanges).map { index -> String in
            guard let groupRange = Range(match.range(at: index), in: text) else { return "" }
            return String(text[groupRange])
        }
        text.replaceSubrange(range, with: " ")
        return groups
    }

    private static func number(_ string: String) -> Int? {
        Int(string) ?? numbers[string.lowercased()]
    }

    private static func repeatInterval(minutes: Int?) -> RepeatInterval? {
        switch minutes {
        case 5: .every5min
        case 15: .every15min
        case 30: .every30min
        case 60: .hourly
        default: nil
        }
    }

    /// Subjunctive left after "il faut que je" → infinitive, for common verbs only.
    private static let infinitives: [String: String] = [
        "finisse": "finir", "rende": "rendre", "fasse": "faire", "appelle": "appeler",
        "rappelle": "rappeler", "envoie": "envoyer", "prépare": "préparer", "révise": "réviser",
        "relance": "relancer", "aille": "aller", "achète": "acheter", "paie": "payer",
        "paye": "payer", "écrive": "écrire", "lise": "lire", "prenne": "prendre",
        "mette": "mettre", "voie": "voir", "dise": "dire", "réponde": "répondre",
        "termine": "terminer", "commence": "commencer", "contacte": "contacter", "vérifie": "vérifier",
        "réserve": "réserver", "passe": "passer", "range": "ranger", "nettoie": "nettoyer",
        "sorte": "sortir", "parte": "partir",
    ]

    private static func cleanTitle(_ text: String) -> String {
        var title = text
        // "il faut que je finisse…" leaves a subjunctive: remember it to restore the infinitive.
        let subjunctiveLead = #"^\s*(?:il\s+)?(?:faut|faudrait)\s+que\s+(?:je\s+|j['’]\s*)"#
        var isSubjunctive = false
        if let regex = try? NSRegularExpression(pattern: subjunctiveLead, options: [.caseInsensitive]),
           regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil {
            isSubjunctive = true
            title = regex.stringByReplacingMatches(in: title, range: NSRange(title.startIndex..., in: title), withTemplate: "")
        }
        let leading = #"^\s*(?:rappelle[- ]moi|rappel|n['’]oublie pas|fais[- ]moi penser|pense|je dois)\s*(?:de\s+|d['’]|à\s+|qu['’]|que\s+)?"#
        if !isSubjunctive, let regex = try? NSRegularExpression(pattern: leading, options: [.caseInsensitive]) {
            title = regex.stringByReplacingMatches(in: title, range: NSRange(title.startIndex..., in: title), withTemplate: "")
        }
        // Collapse spaces, then drop dangling connectors left by removed date fragments.
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let dangling: Set<String> = ["à", "a", "le", "la", "pour", "vers", "de", "et", "ce", "cet", "dans", "du", "au"]
        var words = title.split(separator: " ").map(String.init)
        if isSubjunctive, let first = words.first, let infinitive = infinitives[first.lowercased()] {
            words[0] = infinitive
        }
        while let last = words.last, dangling.contains(last.lowercased().trimmingCharacters(in: .punctuationCharacters)) || last.allSatisfy(\.isPunctuation) {
            words.removeLast()
        }
        title = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?"))
        guard let first = title.first else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return first.uppercased() + title.dropFirst()
    }
}
