import SwiftUI
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
            let parsed = await ParserService.shared.parse(text, spaces: spaces.map(\.ref))
            isParsing = false
            let space = parsed.space.flatMap { ref in spaces.first { $0.id == ref.id } }
            // Session and goal intents are not produced yet (steps 6b / 6c).
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
            onCreated(CaptureOutcome(
                item: item,
                transcript: text,
                proposals: space == nil ? Self.proposals(for: parsed, in: spaces) : []
            ))
            onClose()
        }
    }

    /// The parser's guesses first, then the most used spaces, then the first roots: 3 at most.
    static func proposals(for parsed: ParsedCapture, in spaces: [Space]) -> [Space] {
        var result = parsed.spaceGuesses.compactMap { guess in spaces.first { $0.id == guess.space.id } }
        let byUse = spaces.sorted { $0.tasks.count > $1.tasks.count }.filter { !$0.tasks.isEmpty }
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

/// Result of a dictation, shown in the capture toast.
struct CaptureOutcome: Identifiable {
    let id = UUID()
    let item: TaskItem
    let transcript: String
    /// Suggested spaces when the parser was not confident enough; empty once filed.
    var proposals: [Space]

    var asksForSpace: Bool { item.space == nil && !proposals.isEmpty }
}

/// Black capsule above the tab bar: what was created and where, with "Changer",
/// or "Dans quel espace ?" with 3 suggestions and "Aucun".
struct CaptureToastView: View {
    let outcome: CaptureOutcome
    var onPick: (Space?) -> Void
    var onChange: () -> Void

    private var kind: String { outcome.item.isReminder ? "Rappel ajouté" : "Tâche ajoutée" }

    private var headline: String {
        if outcome.asksForSpace { return "\(kind) · Dans quel espace ?" }
        guard let space = outcome.item.space else { return "\(kind), sans espace" }
        return "\(kind) dans \(space.displayPath)"
    }

    private var detail: String {
        guard let dueDate = outcome.item.dueDate else { return outcome.transcript }
        return "\(VoiceCaptureView.dayAndTime(for: dueDate)) · \(outcome.transcript)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: outcome.asksForSpace ? "questionmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(outcome.asksForSpace ? .white : Palette.green)
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
                if !outcome.asksForSpace {
                    Button("Changer", action: onChange)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(.white.opacity(0.16), in: .capsule)
                        .buttonStyle(.plain)
                }
            }
            if outcome.asksForSpace {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(outcome.proposals) { space in
                            chip(space.name, color: space.color) { onPick(space) }
                        }
                        chip("Aucun", color: nil) { onPick(nil) }
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
