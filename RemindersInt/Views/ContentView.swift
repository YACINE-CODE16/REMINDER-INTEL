import SwiftUI
import SwiftData

/// Root view: current tab content plus the floating tab bar.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppStorageKey.hasSeededDemoData) private var hasSeededDemoData = false
    @AppStorage(AppStorageKey.defaultRepeatInterval) private var defaultRepeatInterval: RepeatInterval = .every15min

    @State private var selectedTab: AppTab = .day
    @State private var selectedDate = Calendar.app.startOfDay(for: .now)
    @State private var isAddingReminder = false
    @State private var notificationReminder: Reminder?

    private let notifications = NotificationService.shared

    var body: some View {
        ZStack {
            AppBackground()

            switch selectedTab {
            case .day:
                DayView(selectedDate: $selectedDate) { selectedTab = .month }
            case .month:
                MonthView(selectedDate: $selectedDate) { selectedTab = .day }
            case .settings:
                SettingsView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            FloatingTabBar(selectedTab: $selectedTab) {
                // Manual entry for now; voice capture comes in step 3.
                isAddingReminder = true
            }
        }
        .sheet(isPresented: $isAddingReminder) {
            ReminderFormView(
                initialDate: ReminderFormView.suggestedDueDate(on: selectedTab == .settings ? .now : selectedDate),
                repeatInterval: defaultRepeatInterval
            )
        }
        .sheet(item: $notificationReminder) { reminder in
            ReminderDetailView(reminder: reminder)
        }
        .task {
            if !hasSeededDemoData {
                DemoData.insert(into: modelContext)
                try? modelContext.save()
                hasSeededDemoData = true
            }
            await notifications.requestAuthorization()
            // Safety net after a reinstall or a missed update.
            notifications.rescheduleAllPending()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { notifications.syncSentCounts() }
        }
        .onChange(of: notifications.reminderToOpen, initial: true) { _, id in
            guard let id else { return }
            notifications.reminderToOpen = nil
            selectedTab = .day
            // A deleted reminder simply leaves the app on the day view.
            guard let reminder = notifications.reminder(with: id) else { return }
            selectedDate = Calendar.app.startOfDay(for: reminder.dueDate)
            notificationReminder = reminder
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Reminder.self, inMemory: true)
}
