import SwiftUI
import SwiftData

/// Voice capture panel: live transcript, waveform, green validate button.
/// Shown as an overlay by the root view, over the dimmed and blurred app.
struct VoiceCaptureView: View {
    /// Called with the confirmation message once the reminder is created.
    var onCreated: (String) -> Void
    /// Called when no date was dictated, so the form can ask for one.
    var onNeedsDate: (_ title: String, _ transcript: String) -> Void
    /// Closes the panel.
    var onClose: () -> Void

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
        .task { await speech.start() }
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
            let parsed = await ParserService.shared.parse(text)
            isParsing = false
            guard let dueDate = parsed.dueDate else {
                onNeedsDate(parsed.title, text)
                onClose()
                return
            }
            let reminder = Reminder(
                title: parsed.title,
                dueDate: dueDate,
                repeatInterval: parsed.repeatInterval ?? defaultRepeatInterval,
                rawTranscript: text
            )
            modelContext.insert(reminder)
            try? modelContext.save()
            NotificationService.shared.schedule(reminder)
            onCreated(Self.confirmation(for: dueDate))
            onClose()
        }
    }

    /// "Rappel créé pour jeudi 16:00", "… pour demain 09:00", "… pour jeu. 22 oct. 16:00".
    static func confirmation(for date: Date, now: Date = .now) -> String {
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
        return "Rappel créé pour \(day) \(time)"
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

/// Small glass confirmation shown at the top of the screen.
struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Palette.text)
            .symbolRenderingMode(.multicolor)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular.tint(.white.opacity(0.6)), in: .capsule)
    }
}
