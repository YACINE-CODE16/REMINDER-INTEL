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
        var rest = text
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

        let dueDate = resolveDate(minutesOffset: minutesOffset, dayOffset: dayOffset, hour: hour ?? partOfDayHour, minute: minute)
        let intent = Self.intent(
            of: text,
            hasRepeat: repeatInterval != nil,
            hasExplicitTime: hour != nil || minutesOffset != nil
        )
        let capture = ParsedCapture(
            intent: intent,
            title: Self.cleanTitle(rest),
            dueDate: dueDate,
            repeatInterval: repeatInterval,
            confidence: dueDate == nil ? 0.3 : 0.6,
            spaceGuesses: SpaceRouter(spaces: spaces).route(text),
            engine: .fallback
        )
        return Output(capture: capture, isRelativeOffset: minutesOffset != nil)
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

    private func resolveDate(minutesOffset: Int?, dayOffset: Int?, hour: Int?, minute: Int?) -> Date? {
        if let minutesOffset {
            return calendar.date(byAdding: .minute, value: minutesOffset, to: now)
        }
        guard dayOffset != nil || hour != nil else { return nil }
        let startOfToday = calendar.startOfDay(for: now)
        guard let day = calendar.date(byAdding: .day, value: dayOffset ?? 0, to: startOfToday),
              let date = calendar.date(bySettingHour: hour ?? 9, minute: minute ?? 0, second: 0, of: day)
        else { return nil }
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

    private static func cleanTitle(_ text: String) -> String {
        var title = text
        let leading = #"^\s*(?:rappelle[- ]moi|rappel|n['’]oublie pas|fais[- ]moi penser|pense|il faut que je|il faudrait que je|faut que je|je dois)\s*(?:de\s+|d['’]|à\s+|qu['’]|que\s+)?"#
        if let regex = try? NSRegularExpression(pattern: leading, options: [.caseInsensitive]) {
            title = regex.stringByReplacingMatches(in: title, range: NSRange(title.startIndex..., in: title), withTemplate: "")
        }
        // Collapse spaces, then drop dangling connectors left by removed date fragments.
        title = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let dangling: Set<String> = ["à", "a", "le", "la", "pour", "vers", "de", "et", "ce", "cet", "dans", "du", "au"]
        var words = title.split(separator: " ").map(String.init)
        while let last = words.last, dangling.contains(last.lowercased().trimmingCharacters(in: .punctuationCharacters)) || last.allSatisfy(\.isPunctuation) {
            words.removeLast()
        }
        title = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?"))
        guard let first = title.first else { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return first.uppercased() + title.dropFirst()
    }
}
