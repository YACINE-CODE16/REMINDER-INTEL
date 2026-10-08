import AppIntents
import Foundation
import Observation

/// Opens the app directly on the voice capture, from the lock screen / Control Center control.
struct StartVoiceCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Nouveau rappel vocal"
    static let description = IntentDescription("Ouvre RemindersInt directement en écoute.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        VoiceCaptureRequests.shared.request()
        return .result()
    }
}

/// Pending "start dictation" requests. The intent may run in the app process (state change
/// observed by the root view) or in the widget extension (timestamp read from the App Group
/// when the app becomes active); both paths are handled.
@MainActor
@Observable
final class VoiceCaptureRequests {
    static let shared = VoiceCaptureRequests()

    /// Bumped on each in-process request so the root view can react.
    private(set) var count = 0
    @ObservationIgnored private var handledCount = 0

    private static let timestampKey = "voiceCaptureRequestedAt"
    /// A request older than this (e.g. Face ID abandoned) is ignored.
    private static let maxAge: TimeInterval = 30

    func request() {
        count += 1
        AppGroup.defaults?.set(Date.now.timeIntervalSince1970, forKey: Self.timestampKey)
    }

    /// True once per request, whichever process recorded it.
    func takePending(now: Date = .now) -> Bool {
        let inProcess = count != handledCount
        handledCount = count
        var fromGroup = false
        if let defaults = AppGroup.defaults, let timestamp = defaults.object(forKey: Self.timestampKey) as? Double {
            fromGroup = now.timeIntervalSince1970 - timestamp < Self.maxAge
            defaults.removeObject(forKey: Self.timestampKey)
        }
        return inProcess || fromGroup
    }
}
