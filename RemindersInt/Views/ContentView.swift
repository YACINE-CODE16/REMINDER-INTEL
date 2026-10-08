import SwiftUI
import SwiftData

/// Root view: current tab content plus the floating tab bar.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.hasSeededDemoData) private var hasSeededDemoData = false
    @AppStorage(AppStorageKey.defaultRepeatInterval) private var defaultRepeatInterval: RepeatInterval = .every15min

    @State private var selectedTab: AppTab = .day
    @State private var selectedDate = Calendar.app.startOfDay(for: .now)
    @State private var isAddingReminder = false

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
        .task {
            guard !hasSeededDemoData else { return }
            DemoData.insert(into: modelContext)
            hasSeededDemoData = true
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Reminder.self, inMemory: true)
}
