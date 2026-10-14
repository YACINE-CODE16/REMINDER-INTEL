import ActivityKit
import AppIntents
import Foundation

/// Live Activity of the running session (lock screen and Dynamic Island). Updated locally only.
nonisolated struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        /// "Études · TAGE MAGE".
        var spacePath: String
        var colorHex: String
        var symbol: String
    }

    var sessionID: UUID
}

/// Stop button of the Live Activity. A LiveActivityIntent runs in the app's process.
struct StopSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Arrêter la session"
    static let description = IntentDescription("Arrête la session de suivi en cours.")

    @MainActor
    func perform() async throws -> some IntentResult {
        if let stop = SessionControl.stop {
            stop()
        } else {
            // App code not loaded in this process: leave the request for the app.
            SessionControl.requestStop()
        }
        return .result()
    }
}

/// Bridge from the shared intent to the app's TrackingService.
@MainActor
enum SessionControl {
    /// Set by the app at launch.
    static var stop: (() -> Void)?

    private static let stopKey = "sessionStopRequestedAt"

    static func requestStop(now: Date = .now) {
        AppGroup.defaults?.set(now.timeIntervalSince1970, forKey: stopKey)
    }

    /// Time of a stop requested while the app could not handle it, consumed once.
    static func takeStopRequest() -> Date? {
        guard let defaults = AppGroup.defaults, let timestamp = defaults.object(forKey: stopKey) as? Double else { return nil }
        defaults.removeObject(forKey: stopKey)
        return Date(timeIntervalSince1970: timestamp)
    }
}
