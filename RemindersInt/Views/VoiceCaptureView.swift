import SwiftUI
import UIKit
import SwiftData

/// Voice capture panel: live transcript, waveform, green validate button.
/// Shown as an overlay by the root view, over the dimmed and blurred app.
struct VoiceCaptureView: View {
    /// Called once the task is created, with the routing result for the toast.
    var onCreated: (CaptureOutcome) -> Void
    /// Called when a reminder was dictated without a date, so the form can ask for one.
    var onNeedsDate: (VoiceDraft) -> Void
    /// Closes the panel.
    var onClose: () -> Void
    /// DEBUG screenshots: text typed into the simulated dictation and validated on appear.
    var autoSubmitText: String? = nil

    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.defaultRepeatInterval) private var defaultRepeatInterval: RepeatInterval = .every15min

    @State private var speech = SpeechService()
    @State private var isParsing = false
    @State private var dragOffset: CGFloat = 0
    #if DEBUG
    @State private var simulatedText = ""
    #endif

    private var currentText: String {
        #if DEBUG
        if !simulatedText.isEmpty { return simulatedText }
        #endif
        return speech.transcript
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusRow

            Text(currentText.isEmpty ? "Dites votre rappel…" : currentText)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(currentText.isEmpty ? .white.opacity(0.5) : .white)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .animation(.default, value: currentText)

            #if DEBUG
            TextField("Simuler une dictée", text: $simulatedText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { validate() }
            #endif

            HStack(spacing: 16) {
                WaveformView(level: speech.level)
                    .frame(height: 44)
                validateButton
            }
        }
        .padding(22)
        .glassEffect(.regular.tint(.black.opacity(0.25)), in: .rect(cornerRadius: 30))
        .glassRim(.rect(cornerRadius: 30), opacity: 0.25)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .offset(y: dragOffset)
        // Swipe down to close, like the former sheet.
        .gesture(
            DragGesture()
                .onChanged { dragOffset = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 80 {
                        onClose()
                    } else {
                        withAnimation(.appSpring) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
        .task {
            #if DEBUG
            if let autoSubmitText {
                simulatedText = autoSubmitText
                validate()
                return
            }
            #endif
            await speech.start()
        }
        .onDisappear { speech.stop() }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 8) {
            if isParsing {
                ProgressView()
                Text("Analyse…")
            } else if let error = speech.errorMessage, speech.isPermissionDenied {
                PermissionBanner(
                    message: error,
                    systemImage: "mic.slash.fill",
                    settingsURL: UIApplication.openSettingsURLString,
                    onDark: true
                )
            } else if let error = speech.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.red)
                Text(error)
            } else if speech.isListening {
                Circle()
                    .fill(Palette.red)
                    .frame(width: 10, height: 10)
                    .phaseAnimator([1.0, 0.35]) { dot, opacity in dot.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.8) }
                Text("En écoute")
            } else {
                Text("Micro inactif")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white.opacity(0.75))
    }

    private var validateButton: some View {
        Button(action: validate) {
            Group {
                if isParsing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Palette.green).interactive(), in: .rect(cornerRadius: 20))
        .glassRim(.rect(cornerRadius: 20), opacity: 0.4)
        .disabled(isParsing || currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel("Valider")
    }

    private func validate() {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isParsing else { return }
        speech.stop()
        isParsing = true
        Task {
            let spaces = Space.activeTree(in: modelContext)
            let parsed = await ParserService.shared.parse(text, spaces: spaces.map(\.ref), gym: Self.gymContext())
            isParsing = false
            let space = parsed.space.flatMap { ref in spaces.first { $0.id == ref.id } }
            let proposals = space == nil ? Self.proposals(for: parsed, in: spaces) : []
            if parsed.intent.isSession {
                onCreated(Self.handleSession(parsed, space: space, proposals: proposals, transcript: text))
                onClose()
                return
            }
            if parsed.intent.isGym, let command = parsed.gym {
                onCreated(Self.handleGym(parsed.intent, command: command, transcript: text))
                onClose()
                return
            }
            if parsed.intent == .prayerCheck, let check = parsed.prayerCheck {
                onCreated(Self.handlePrayer(check, transcript: text))
                onClose()
                return
            }
            if parsed.intent == .goalProgress {
                let goals = (try? modelContext.fetch(FetchDescriptor<Goal>())) ?? []
                let guessed = parsed.spaceGuesses.compactMap { guess in spaces.first { $0.id == guess.space.id } }
                onCreated(Self.handleGoalProgress(text: text, guessedSpaces: guessed, goals: goals))
                try? modelContext.save()
                onClose()
                return
            }
            let isReminder = parsed.intent == .reminder
            if isReminder, parsed.dueDate == nil {
                onNeedsDate(VoiceDraft(title: parsed.title, transcript: text, space: space))
                onClose()
                return
            }
            let item = TaskItem(
                title: parsed.title,
                dueDate: parsed.dueDate,
                repeatInterval: isReminder ? (parsed.repeatInterval ?? defaultRepeatInterval) : .none,
                rawTranscript: text,
                isReminder: isReminder,
                space: space
            )
            modelContext.insert(item)
            try? modelContext.save()
            NotificationService.shared.schedule(item)
            onCreated(CaptureOutcome(kind: .task(item), transcript: text, proposals: proposals))
            onClose()
        }
    }

    /// Start, stop or log a session. Without a confident space, the toast asks for one.
    static func handleSession(_ parsed: ParsedCapture, space: Space?, proposals: [Space], transcript: String) -> CaptureOutcome {
        let tracking = TrackingService.shared
        let now = Date.now
        switch parsed.intent {
        case .sessionStop:
            return CaptureOutcome(kind: .sessionStopped(tracking.stop(at: now)), transcript: transcript, proposals: [])
        case .sessionLog:
            let length = parsed.duration ?? 3600
            var start = parsed.dueDate ?? now.addingTimeInterval(-length)
            // A past session cannot end in the future.
            if start.addingTimeInterval(length) > now { start = now.addingTimeInterval(-length) }
            let end = start.addingTimeInterval(length)
            guard let space else {
                return CaptureOutcome(kind: .pendingSession(PendingSession(isLog: true, start: start, end: end)), transcript: transcript, proposals: proposals)
            }
            let sessions = tracking.log(in: space, from: start, to: end, transcript: transcript)
            return CaptureOutcome(kind: .sessionLogged(sessions), transcript: transcript, proposals: [])
        default:
            guard let space, let session = tracking.start(in: space, at: now, transcript: transcript) else {
                return CaptureOutcome(kind: .pendingSession(PendingSession(isLog: false, start: now)), transcript: transcript, proposals: proposals)
            }
            return CaptureOutcome(kind: .sessionStarted(session), transcript: transcript, proposals: [])
        }
    }

    /// Exercises and programmes for the parser, only when a space runs the gym module.
    static func gymContext() -> GymContext {
        let gym = GymService.shared
        guard gym.gymSpace() != nil else { return .empty }
        return GymContext(
            exercises: gym.exercises().map(\.ref),
            templates: gym.templates().map(\.name),
            isWorkoutActive: gym.activeWorkout() != nil
        )
    }

    /// gym.set / next / finish / start. A set without a running workout starts a free session.
    static func handleGym(_ intent: CaptureIntent, command: GymCommand, transcript: String) -> CaptureOutcome {
        let gym = GymService.shared
        func outcome(_ kind: CaptureOutcome.Kind) -> CaptureOutcome {
            CaptureOutcome(kind: kind, transcript: transcript, proposals: [])
        }
        guard gym.gymSpace() != nil else { return outcome(.gymMessage("Module Salle inactif")) }
        switch intent {
        case .gymStart:
            if let active = gym.activeWorkout() { return outcome(.gymMessage("Séance \(active.name) déjà en cours")) }
            let template: WorkoutTemplate? = if command.isFreeSession {
                nil
            } else if let name = command.templateName {
                gym.templates().first { $0.name == name }
            } else {
                gym.suggestedTemplate()
            }
            guard let workout = gym.start(template: template, transcript: transcript) else { return outcome(.gymMessage("Impossible de démarrer la séance")) }
            gym.requestWorkoutScreen()
            return outcome(.gymStarted(workout))
        case .gymNext:
            guard let workout = gym.activeWorkout() else { return outcome(.gymMessage("Aucune séance en cours")) }
            guard let entry = gym.next(in: workout) else { return outcome(.gymMessage("Dernier exercice de la séance")) }
            return outcome(.gymNext(workout, name: entry.exercise?.nameFR ?? "Exercice"))
        case .gymFinish:
            guard let workout = gym.activeWorkout() else { return outcome(.gymMessage("Aucune séance en cours")) }
            return outcome(.gymFinished(workout, gym.finish(workout)))
        default:
            let exercise = command.exerciseID.flatMap { id in gym.exercises().first { $0.id == id } }
            let workout = gym.activeWorkout() ?? gym.start(template: nil, transcript: transcript)
            guard let workout else { return outcome(.gymMessage("Impossible de démarrer la séance")) }
            guard let target = exercise ?? workout.currentEntry?.exercise else { return outcome(.gymMessage("Exercice non reconnu")) }
            guard let value = command.set(for: target.kind) else { return outcome(.gymMessage("Série incomplète · \(target.nameFR)")) }
            guard let set = gym.addSet(to: exercise, in: workout, reps: value.reps, weight: value.weight, seconds: value.seconds, meters: value.meters) else {
                return outcome(.gymMessage("Exercice non reconnu"))
            }
            let number = set.entry?.sets.count ?? 1
            return outcome(.gymSet(set, number: number, exercise: target.nameFR, kind: target.kind))
        }
    }

    /// Ticks the prayer of today, or of yesterday ("d'hier", or Isha said before today's Fajr).
    static func handlePrayer(_ check: PrayerCheck, transcript: String, now: Date = .now) -> CaptureOutcome {
        let service = PrayerService.shared
        guard let settings = service.settings() else {
            return CaptureOutcome(kind: .prayerUnavailable, transcript: transcript, proposals: [])
        }
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: now)
        var isYesterday = check.isYesterday
        if !isYesterday, check.prayer == .isha, now < service.times(on: today, settings: settings).fajr {
            isYesterday = true
        }
        let day = isYesterday ? (calendar.date(byAdding: .day, value: -1, to: today) ?? today) : today
        let mark: PrayerMark = switch check.mark {
        case .done: .auto
        case .onTime: .onTime
        case .late: .late
        case .madeUp: .madeUp
        }
        guard let record = service.check(check.prayer, on: day, at: now, mark: mark) else {
            return CaptureOutcome(kind: .prayerUnavailable, transcript: transcript, proposals: [])
        }
        let name = check.prayer.name(on: day, calendar: calendar)
        return CaptureOutcome(kind: .prayerChecked(name: name, status: record.status, isYesterday: isYesterday), transcript: transcript, proposals: [])
    }

    /// +1 on the counter goal the sentence points to: by its title or unit ("club" → "clubs"),
    /// else by the guessed spaces, else any counter. Several candidates: the toast asks.
    static func handleGoalProgress(text: String, guessedSpaces: [Space], goals: [Goal]) -> CaptureOutcome {
        let candidates = goalCandidates(text: text, guessedSpaces: guessedSpaces, goals: goals)
        switch candidates.count {
        case 0:
            return CaptureOutcome(kind: .goalNotFound, transcript: text, proposals: [])
        case 1:
            GoalMath.increment(candidates[0])
            return CaptureOutcome(kind: .goalProgress(candidates[0]), transcript: text, proposals: [])
        default:
            return CaptureOutcome(kind: .goalChoice(Array(candidates.prefix(4))), transcript: text, proposals: [])
        }
    }

    static func goalCandidates(text: String, guessedSpaces: [Space], goals: [Goal]) -> [Goal] {
        let counters = goals.filter { $0.kind == .count && !$0.isArchived }
        var candidates = counters.filter { mentions($0, in: text) }
        if candidates.isEmpty {
            for space in guessedSpaces {
                candidates = counters.filter { goal in goal.space.map(space.contains) ?? false }
                if !candidates.isEmpty { break }
            }
        }
        return candidates.isEmpty ? counters : candidates
    }

    /// A word of 4+ letters of the goal's title or unit appears in the sentence, plural ignored.
    private static func mentions(_ goal: Goal, in text: String) -> Bool {
        func stems(_ string: String) -> Set<String> {
            Set(SpaceRouter.normalize(string).split(separator: " ").map { word in
                word.hasSuffix("s") ? String(word.dropLast()) : String(word)
            }.filter { $0.count >= 4 })
        }
        return !stems(goal.title + " " + (goal.unit ?? "")).isDisjoint(with: stems(text))
    }

    /// The parser's guesses first, then the most used spaces, then the first roots: 3 at most.
    static func proposals(for parsed: ParsedCapture, in spaces: [Space]) -> [Space] {
        var result = parsed.spaceGuesses.compactMap { guess in spaces.first { $0.id == guess.space.id } }
        let use: (Space) -> Int = { $0.tasks.count + $0.sessions.count }
        let byUse = spaces.filter { use($0) > 0 }.sorted { use($0) > use($1) }
        let roots = spaces.filter { $0.parent == nil }
        for candidate in byUse + roots where result.count < 3 && !result.contains(where: { $0.id == candidate.id }) {
            result.append(candidate)
        }
        return Array(result.prefix(3))
    }

    /// "jeudi 16:00", "demain 09:00", "jeu. 22 oct. 16:00".
    static func dayAndTime(for date: Date, now: Date = .now) -> String {
        let calendar = Calendar.app
        let time = date.formatted(.dateTime.hour().minute().locale(.app))
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "aujourd'hui"
        } else if calendar.isDateInTomorrow(date) {
            day = "demain"
        } else if let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day, (0..<7).contains(days) {
            day = date.formatted(.dateTime.weekday(.wide).locale(.app))
        } else {
            day = date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(.app))
        }
        return "\(day) \(time)"
    }
}

/// Dictation-style white bars driven by the recent input levels.
struct WaveformView: View {
    var level: Double

    private static let barCount = 18
    @State private var samples = Array(repeating: 0.0, count: barCount)

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 4) {
                ForEach(samples.indices, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(height: max(4, samples[index] * proxy.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: level) { _, newLevel in
            withAnimation(.linear(duration: 0.08)) {
                samples.removeFirst()
                samples.append(newLevel)
            }
        }
        .accessibilityHidden(true)
    }
}
