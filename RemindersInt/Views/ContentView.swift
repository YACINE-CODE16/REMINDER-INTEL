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
    @State private var isCapturingVoice = false
    @State private var voiceDraft: VoiceDraft?
    @State private var pendingVoiceDraft: VoiceDraft?
    @State private var toastMessage: String?
    @State private var notificationReminder: Reminder?

    private let notifications = NotificationService.shared
    private let captureRequests = VoiceCaptureRequests.shared

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
            FloatingTabBar(
                selectedTab: $selectedTab,
                onMicrophone: { isCapturingVoice = true },
                onManualEntry: { isAddingReminder = true }
            )
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toastMessage) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { self.toastMessage = nil }
                    }
            }
        }
        .sheet(isPresented: $isCapturingVoice, onDismiss: {
            // The form can only be presented once the voice sheet is gone.
            voiceDraft = pendingVoiceDraft
            pendingVoiceDraft = nil
        }) {
            VoiceCaptureView(
                onCreated: { message in withAnimation { toastMessage = message } },
                onNeedsDate: { title, transcript in pendingVoiceDraft = VoiceDraft(title: title, transcript: transcript) }
            )
        }
        .sheet(item: $voiceDraft) { draft in
            ReminderFormView(
                initialDate: ReminderFormView.suggestedDueDate(on: .now),
                repeatInterval: defaultRepeatInterval,
                title: draft.title,
                rawTranscript: draft.transcript
            )
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
            await ParserService.shared.checkModel()
            // Safety net after a reinstall or a missed update.
            notifications.rescheduleAllPending()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            notifications.syncSentCounts()
            // Lock screen control whose intent ran in the widget extension.
            if captureRequests.takePending() { openVoiceCapture() }
        }
        // Lock screen control whose intent ran in the app process.
        .onChange(of: captureRequests.count) {
            if captureRequests.takePending() { openVoiceCapture() }
        }
        .onOpenURL(perform: handleDeepLink)
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

    /// remindersint://capture opens the dictation, remindersint://reminder/<uuid> a detail.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "remindersint" else { return }
        switch url.host() {
        case "capture":
            openVoiceCapture()
        case "reminder":
            if let id = UUID(uuidString: url.lastPathComponent) {
                notifications.reminderToOpen = id
            }
        default:
            break
        }
    }

    /// Closes the root sheets so the capture can be presented; it starts listening on appear.
    private func openVoiceCapture() {
        isAddingReminder = false
        voiceDraft = nil
        notificationReminder = nil
        isCapturingVoice = true
    }
}

/// Dictation without a date, completed in the form.
struct VoiceDraft: Identifiable {
    let id = UUID()
    let title: String
    let transcript: String
}

#Preview {
    ContentView()
        .modelContainer(for: Reminder.self, inMemory: true)
}
