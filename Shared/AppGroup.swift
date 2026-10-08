import Foundation

/// Identifiers shared by the app and the widget extension.
nonisolated enum AppGroup {
    static let identifier = "group.com.yacine.RemindersInt"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}

nonisolated enum WidgetKind {
    static let nextReminder = "com.yacine.RemindersInt.nextReminder"
    static let voiceCapture = "com.yacine.RemindersInt.voiceCapture"
}
