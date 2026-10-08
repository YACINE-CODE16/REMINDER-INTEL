import SwiftUI
import WidgetKit

@main
struct RemindersIntWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoiceCaptureControl()
        NextReminderWidget()
    }
}
