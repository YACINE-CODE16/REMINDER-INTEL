import AppIntents
import SwiftUI
import WidgetKit

/// Control for the lock screen bottom slots and Control Center: one tap opens the app in dictation.
struct VoiceCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.voiceCapture) {
            ControlWidgetButton(action: StartVoiceCaptureIntent()) {
                Label("Dicter un rappel", systemImage: "mic.fill")
            }
        }
        .displayName("Dicter un rappel")
        .description("Ouvre RemindersInt directement en écoute.")
    }
}
