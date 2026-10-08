import AppIntents

/// Exposes the voice capture to Shortcuts, so it can be assigned to the Action button.
struct RemindersIntShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartVoiceCaptureIntent(),
            phrases: [
                "Nouveau rappel dans \(.applicationName)",
                "Dicter un rappel dans \(.applicationName)",
            ],
            shortTitle: "Nouveau rappel vocal",
            systemImageName: "mic.fill"
        )
    }
}
