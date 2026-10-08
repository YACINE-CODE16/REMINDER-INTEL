import SwiftUI
import SwiftData

/// Voice capture panel: live transcript, waveform, green validate button.
struct VoiceCaptureView: View {
    /// Called with the confirmation message once the reminder is created.
    var onCreated: (String) -> Void
    /// Called when no date was dictated, so the form can ask for one.
    var onNeedsDate: (_ title: String, _ transcript: String) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKey.defaultRepeatInterval) private var defaultRepeatInterval: RepeatInterval = .every15min

    @State private var speech = SpeechService()
    @State private var isParsing = false
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
        VStack(alignment: .leading, spacing: 20) {
            statusRow

            Text(currentText.isEmpty ? "Dites votre rappel…" : currentText)
                .font(.title.weight(.semibold))
                .foregroundStyle(currentText.isEmpty ? Palette.secondary : Palette.text)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                .animation(.default, value: currentText)

            #if DEBUG
            TextField("Simuler une dictée", text: $simulatedText)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { validate() }
            #endif

            Spacer(minLength: 0)

            HStack(spacing: 16) {
                WaveformView(level: speech.level)
                    .frame(height: 44)
                validateButton
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
        .foregroundStyle(Palette.secondary)
    }

    private var validateButton: some View {
        Button(action: validate) {
            Group {
                if isParsing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Palette.green).interactive(), in: .circle)
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
                dismiss()
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
            dismiss()
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

/// Dictation-style bars driven by the recent input levels.
struct WaveformView: View {
    var level: Double

    private static let barCount = 28
    @State private var samples = Array(repeating: 0.0, count: barCount)

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .center, spacing: 3) {
                ForEach(samples.indices, id: \.self) { index in
                    Capsule()
                        .fill(Palette.text.opacity(0.75))
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
