import AVFoundation
import Observation
import Speech

/// Live French dictation with SFSpeechRecognizer: partial transcript and input level.
@Observable
final class SpeechService {
    /// Partial transcript, updated in real time while listening.
    private(set) var transcript = ""
    /// Normalized input level 0...1, for the waveform.
    private(set) var level: Double = 0
    private(set) var isListening = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?

    private enum SpeechError: Error {
        case noAudioInput
    }

    func start() async {
        guard !isListening else { return }
        errorMessage = nil
        guard await Self.requestPermissions() else {
            errorMessage = "Autorise le micro et la reconnaissance vocale dans Réglages."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Reconnaissance vocale indisponible."
            return
        }
        do {
            try startRecognition(with: recognizer)
        } catch {
            stop()
            errorMessage = "Micro indisponible."
        }
    }

    func stop() {
        guard request != nil else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        isListening = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startRecognition(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        // installTap raises an Objective-C exception on an empty format (no microphone).
        guard format.channelCount > 0, format.sampleRate > 0 else { throw SpeechError.noAudioInput }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device when the recognizer supports it, Apple's server otherwise.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTapBlock(request: request) { [weak self] level in
            Task { @MainActor in self?.level = level }
        })
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request, resultHandler: Self.makeResultHandler { [weak self] text, isFinished in
            Task { @MainActor in self?.handleResult(text: text, isFinished: isFinished) }
        })
        transcript = ""
        isListening = true
    }

    private func handleResult(text: String?, isFinished: Bool) {
        if let text { transcript = text }
        if isFinished { stop() }
    }

    // MARK: - Off-main callbacks

    // Audio taps and recognition results arrive on background queues. These closures are built
    // in nonisolated functions so they do not inherit the main actor (which would trap at runtime).

    nonisolated private static func makeTapBlock(
        request: SFSpeechAudioBufferRecognitionRequest,
        onLevel: @escaping @Sendable (Double) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            request.append(buffer)
            onLevel(normalizedLevel(of: buffer))
        }
    }

    nonisolated private static func makeResultHandler(
        _ onUpdate: @escaping @Sendable (String?, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            onUpdate(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }

    /// RMS of the first channel mapped from -50...0 dB to 0...1.
    nonisolated private static func normalizedLevel(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            sum += samples[index] * samples[index]
        }
        let decibels = 20 * log10(max(sqrt(sum / Float(count)), 1e-7))
        return Double(min(max((decibels + 50) / 50, 0), 1))
    }

    nonisolated private static func requestPermissions() async -> Bool {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
