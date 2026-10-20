import SwiftUI
import SwiftData

/// Root view: current tab content plus the floating tab bar.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @AppStorage(AppStorageKey.hasSeededDemoData) private var hasSeededDemoData = false
    #endif
    @AppStorage(AppStorageKey.defaultRepeatInterval) private var defaultRepeatInterval: RepeatInterval = .every15min

    @State private var selectedTab: AppTab = .day
    @State private var selectedDate = Calendar.app.startOfDay(for: .now)
    @State private var spacesPath: [Space] = []
    @State private var isAddingReminder = false
    @State private var isShowingSettings = false
    @State private var isCapturingVoice = false
    @State private var voiceDraft: VoiceDraft?
    @State private var pendingVoiceDraft: VoiceDraft?
    @State private var captureOutcome: CaptureOutcome?
    @State private var isChangingSpace = false
    @State private var showsStats = false
    @State private var detailItem: TaskItem?
    @State private var gymSummary: WorkoutSummary?
    #if DEBUG
    @State private var debugDictation: String?
    #endif

    private let notifications = NotificationService.shared
    private let tracking = TrackingService.shared
    private let prayers = PrayerService.shared
    private let captureRequests = VoiceCaptureRequests.shared

    var body: some View {
        ZStack {
            mainContent
                .blur(radius: isCapturingVoice ? 14 : 0)
                .allowsHitTesting(!isCapturingVoice)
                .accessibilityHidden(isCapturingVoice)

            if isCapturingVoice {
                // The app underneath, darkened and blurred.
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture(perform: closeVoiceCapture)
                    .transition(.opacity)
                    .accessibilityHidden(true)

                VStack {
                    Spacer()
                    voiceCapture
                }
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.appSpring, value: isCapturingVoice)
        // Dark status bar text would be unreadable over the dimmed app.
        .statusBarHidden(isCapturingVoice)
        .sheet(item: $voiceDraft) { draft in
            TaskFormView(
                initialDate: TaskFormView.suggestedDueDate(on: .now),
                repeatInterval: defaultRepeatInterval,
                title: draft.title,
                rawTranscript: draft.transcript,
                space: draft.space
            )
        }
        .sheet(isPresented: $isAddingReminder) {
            TaskFormView(
                initialDate: TaskFormView.suggestedDueDate(on: selectedTab == .day || selectedTab == .month ? selectedDate : .now),
                repeatInterval: defaultRepeatInterval
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView()
                    .background(AppBackground())
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(role: .close) { isShowingSettings = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $isChangingSpace) {
            if let captureOutcome {
                SpacePickerSheet(
                    selectedID: captureOutcome.currentSpace?.id,
                    allowsNone: captureOutcome.allowsNone,
                    onPick: changeSpace
                )
            }
        }
        .sheet(item: $gymSummary) { summary in
            WorkoutSummaryView(summary: summary)
        }
        .sheet(item: $detailItem) { item in
            TaskDetailView(item: item)
        }
        .task {
            #if DEBUG
            await applyDebugLaunchArguments()
            // Screenshots on a fresh simulator: no permission alert over the UI.
            if !UserDefaults.standard.bool(forKey: "uiNoPrompt") {
                await notifications.requestAuthorization()
            }
            #else
            await notifications.requestAuthorization()
            #endif
            // Nothing is scheduled before the prompt is answered: requests made meanwhile
            // (evening reminders, prayers…) waited in the budget queue and go out now.
            await notifications.refreshAuthorizationStatus()
            NotificationBudget.authorizationResolved()
            await ParserService.shared.checkModel()
            // Safety net after a reinstall or a missed update.
            rescheduleNotifications()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            notifications.syncSentCounts()
            tracking.resume()
            prayers.resume()
            // A workout stopped from the Live Activity (or elsewhere) while away: its summary, once.
            if let summary = GymService.shared.takePendingSummary() { gymSummary = summary }
            // Permission granted in Réglages since last time: schedule everything again.
            Task {
                if await notifications.refreshAuthorizationStatus() { rescheduleNotifications() }
            }
            // Lock screen control whose intent ran in the widget extension.
            if captureRequests.takePending() { openVoiceCapture() }
        }
        // Lock screen control whose intent ran in the app process.
        .onChange(of: captureRequests.count) {
            if captureRequests.takePending() { openVoiceCapture() }
        }
        .onOpenURL(perform: handleDeepLink)
        .onChange(of: tracking.showTrackingRequests) {
            closeSheets()
            selectedTab = .tracking
        }
        .onChange(of: prayers.showPrayerSpaceRequests) {
            openPrayerSpace()
        }
        .onChange(of: GymService.shared.showWorkoutRequests) {
            open(GymService.shared.gymSpace())
        }
        .onChange(of: notifications.taskToOpen, initial: true) { _, id in
            guard let id else { return }
            notifications.taskToOpen = nil
            selectedTab = .day
            // A deleted task simply leaves the app on the day view.
            guard let item = notifications.task(with: id) else { return }
            if let dueDate = item.dueDate {
                selectedDate = Calendar.app.startOfDay(for: dueDate)
            }
            detailItem = item
        }
    }

    private var mainContent: some View {
        ZStack {
            AppBackground()

            switch selectedTab {
            case .day:
                DayView(
                    selectedDate: $selectedDate,
                    onShowCalendar: { withAnimation(.appSpring) { selectedTab = .month } },
                    onShowSettings: { isShowingSettings = true },
                    onSelect: { detailItem = $0 }
                )
            case .month:
                MonthView(
                    selectedDate: $selectedDate,
                    onShowDay: { withAnimation(.appSpring) { selectedTab = .day } },
                    onSelect: { detailItem = $0 }
                )
            case .spaces:
                SpacesHubView(path: $spacesPath, onSelectTask: { detailItem = $0 })
            case .tracking:
                TrackingView(showsStats: $showsStats)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if let captureOutcome {
                    CaptureToastView(
                        outcome: captureOutcome,
                        onPick: answer,
                        onChange: { isChangingSpace = true },
                        onPickGoal: { goal in
                            GoalMath.increment(goal)
                            try? modelContext.save()
                            showToast(.goalProgress(goal), from: captureOutcome)
                        },
                        onUndo: { undo(captureOutcome) }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // Restarted when the space picker opens or closes: no auto-close while the
                    // picker is up, a full delay again once it is closed.
                    .task(id: "\(captureOutcome.id)-\(isChangingSpace)") {
                        guard !isChangingSpace else { return }
                        // Longer when a question is asked.
                        try? await Task.sleep(for: .seconds(captureOutcome.asksQuestion ? 10 : 6))
                        guard !Task.isCancelled else { return }
                        withAnimation(.appSpring) { self.captureOutcome = nil }
                    }
                }
                FloatingTabBar(
                    selectedTab: $selectedTab,
                    onMicrophone: { isCapturingVoice = true },
                    onManualEntry: { isAddingReminder = true }
                )
            }
            .animation(.appSpring, value: captureOutcome?.id)
        }
    }

    private var voiceCapture: some View {
        #if DEBUG
        let autoSubmit = debugDictation
        #else
        let autoSubmit: String? = nil
        #endif
        return VoiceCaptureView(
            onCreated: { captureOutcome = $0 },
            onNeedsDate: { pendingVoiceDraft = $0 },
            onClose: closeVoiceCapture,
            autoSubmitText: autoSubmit
        )
    }

    /// Answer to "Dans quel espace ?": files the task or creates the pending session.
    private func answer(_ space: Space?) {
        guard let outcome = captureOutcome else { return }
        switch outcome.kind {
        case .task(let item):
            file(item, in: space)
            showToast(.task(item), from: outcome)
        case .pendingSession(let pending):
            guard let space else { return }
            if pending.isLog, let end = pending.end {
                showToast(.sessionLogged(tracking.log(in: space, from: pending.start, to: end, transcript: outcome.transcript)), from: outcome)
            } else if let session = tracking.start(in: space, at: pending.start, transcript: outcome.transcript) {
                showToast(.sessionStarted(session), from: outcome)
            }
        default:
            break
        }
    }

    /// "Annuler" on the toast: +1 removed, set deleted, previous exercise, workout reopened or cancelled.
    private func undo(_ outcome: CaptureOutcome) {
        let gym = GymService.shared
        switch outcome.kind {
        case .goalProgress(let goal):
            GoalMath.increment(goal, by: -1)
            try? modelContext.save()
            showToast(.goalUndone(goal), from: outcome)
        case .gymSet(let set, let number, _, _):
            gym.delete(set)
            showToast(.gymMessage("S\(number) supprimée"), from: outcome)
        case .gymNext(let workout, _):
            gym.previous(in: workout)
            showToast(.gymMessage("Retour à \(workout.currentEntry?.exercise?.nameFR ?? "l'exercice précédent")"), from: outcome)
        case .gymFinished(let workout, _):
            gym.reopen(workout)
            showToast(.gymMessage("Séance \(workout.name) reprise"), from: outcome)
        case .gymStarted(let workout):
            gym.cancel(workout)
            showToast(.gymMessage("Séance annulée"), from: outcome)
        default:
            break
        }
    }

    /// "Changer" on the toast: moves the task or the sessions to another space.
    private func changeSpace(_ space: Space?) {
        guard let outcome = captureOutcome else { return }
        switch outcome.kind {
        case .task(let item):
            file(item, in: space)
        case .sessionStarted(let session):
            if let space { tracking.move([session], to: space) }
        case .sessionLogged(let sessions):
            if let space { tracking.move(sessions, to: space) }
        default:
            break
        }
        showToast(outcome.kind, from: outcome)
    }

    private func file(_ item: TaskItem, in space: Space?) {
        item.space = space
        try? modelContext.save()
        NotificationService.shared.schedule(item)
    }

    /// Shows the updated result, with a fresh display time and no more suggestions.
    private func showToast(_ kind: CaptureOutcome.Kind, from outcome: CaptureOutcome) {
        captureOutcome = CaptureOutcome(kind: kind, transcript: outcome.transcript, proposals: [])
    }

    /// A dictation without a date continues in the form once the panel is closed.
    private func closeVoiceCapture() {
        isCapturingVoice = false
        voiceDraft = pendingVoiceDraft
        pendingVoiceDraft = nil
        #if DEBUG
        debugDictation = nil
        #endif
    }

    #if DEBUG
    /// Screenshot and test helpers:
    /// `-uiDayOffset <n>` (day shown in the day view), `-seedDemoData YES` (sample reminders and tasks, once), `-seedDemoSessions YES` (two weeks of sessions, once), `-seedDemoGoals YES` (3 goals per kind, once), `-seedDemoPrayer YES` ("Prière" space, 20 weeks of prayers, once; `-resetDemoPrayer YES` first to redo it), `-prayerNotificationTest YES` (adhan in 5 s + follow-up), `-seedDemoGym YES` ("Salle" space, 20 weeks of workouts, once; `-resetDemoGym YES` first to redo it), `-prayerLogNotifications YES` (prints pending prayer requests), `-uiTab day|month|spaces|tracking|stats|settings`, `-uiSpace <name>` (opens that space),
    /// `-uiScreen capture|detail|form`, `-uiDictation "<phrase>"` (validated through the
    /// simulated dictation field), `-parserSelfTest YES` (prints the routing table).
    private func applyDebugLaunchArguments() async {
        let defaults = UserDefaults.standard
        // Sample reminders and tasks: DEBUG only, on request; a release install starts empty
        // (only the default spaces of StoreSetup).
        if defaults.bool(forKey: "seedDemoData"), !hasSeededDemoData {
            DemoData.insert(into: modelContext)
            try? modelContext.save()
            hasSeededDemoData = true
        }
        if defaults.bool(forKey: "seedDemoSessions") {
            DemoSessions.insert(into: modelContext)
        }
        if defaults.bool(forKey: "seedDemoGoals") {
            DemoGoals.insert(into: modelContext)
        }
        if defaults.bool(forKey: "resetDemoPrayer") {
            DemoPrayer.reset(in: modelContext)
        }
        if defaults.bool(forKey: "seedDemoPrayer") {
            DemoPrayer.insert(into: modelContext)
            prayers.refresh()
        }
        if defaults.bool(forKey: "resetDemoGym") {
            DemoGym.reset(in: modelContext)
        }
        if defaults.bool(forKey: "seedDemoGym") {
            DemoGym.insert(into: modelContext)
        }
        if defaults.bool(forKey: "prayerNotificationTest") {
            // Once the launch has answered authorization and rebuilt the real requests.
            Task {
                try? await Task.sleep(for: .seconds(3))
                prayers.scheduleTestNotifications()
            }
        }
        if defaults.bool(forKey: "prayerLogNotifications") {
            // After the launch rescheduling, which runs once authorization is answered.
            Task {
                try? await Task.sleep(for: .seconds(4))
                await PrayerService.logPendingRequests()
            }
        }
        switch defaults.string(forKey: "uiTab") {
        case "month": selectedTab = .month
        case "spaces": selectedTab = .spaces
        case "tracking": selectedTab = .tracking
        case "stats":
            selectedTab = .tracking
            showsStats = true
        case "settings": isShowingSettings = true
        default: break
        }
        if let name = defaults.string(forKey: "uiSpace"),
           let space = Space.activeTree(in: modelContext).first(where: { $0.name == name }) {
            selectedTab = .spaces
            var chain: [Space] = []
            var current: Space? = space
            while let node = current {
                chain.insert(node, at: 0)
                current = node.parent
            }
            spacesPath = chain
        }
        if defaults.object(forKey: "uiDayOffset") != nil {
            let offset = defaults.integer(forKey: "uiDayOffset")
            selectedDate = Calendar.app.date(byAdding: .day, value: offset, to: Calendar.app.startOfDay(for: .now)) ?? selectedDate
        }
        switch defaults.string(forKey: "uiScreen") {
        case "capture": isCapturingVoice = true
        case "form": isAddingReminder = true
        case "detail":
            let items = ((try? modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []).sorted(by: TaskItem.byDueDate)
            detailItem = items.first { $0.dueDate.map { Calendar.app.isDate($0, inSameDayAs: selectedDate) } ?? false } ?? items.first
        default: break
        }
        if let phrase = defaults.string(forKey: "uiDictation") {
            debugDictation = phrase
            isCapturingVoice = true
        }
        if defaults.bool(forKey: "parserSelfTest") {
            await ParserSelfTest.run(spaces: Space.activeTree(in: modelContext).map(\.ref))
            ParserSelfTest.goalChecks(in: modelContext)
        }
    }
    #endif

    /// remindersint://capture opens the dictation, remindersint://reminder/<uuid> a detail,
    /// remindersint://tracking the Suivi tab (Live Activity tap).
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "remindersint" else { return }
        switch url.host() {
        case "capture":
            openVoiceCapture()
        case "tracking":
            closeSheets()
            selectedTab = .tracking
        case "prayer":
            openPrayerSpace()
        case "reminder":
            if let id = UUID(uuidString: url.lastPathComponent) {
                notifications.taskToOpen = id
            }
        default:
            break
        }
    }

    /// Closes the root sheets so the capture can be presented; it starts listening on appear.
    private func openVoiceCapture() {
        closeSheets()
        isCapturingVoice = true
    }

    /// Every service's notifications, from the store.
    private func rescheduleNotifications() {
        notifications.rescheduleAllPending()
        prayers.resume()
        tracking.rescheduleNotifications()
    }

    /// Notification or widget tap: the space running the prayer module, in the Espaces tab.
    private func openPrayerSpace() {
        open(prayers.prayerSpace())
    }

    /// Shows a space (and its ancestors) in the Espaces tab.
    private func open(_ space: Space?) {
        closeSheets()
        selectedTab = .spaces
        guard let space else { return }
        var chain: [Space] = []
        var current: Space? = space
        while let node = current {
            chain.insert(node, at: 0)
            current = node.parent
        }
        spacesPath = chain
    }

    private func closeSheets() {
        isAddingReminder = false
        isShowingSettings = false
        voiceDraft = nil
        detailItem = nil
        isChangingSpace = false
    }
}

/// Reminder dictated without a date, completed in the form.
struct VoiceDraft: Identifiable {
    let id = UUID()
    let title: String
    let transcript: String
    var space: Space?
}

#Preview {
    ContentView()
        .modelContainer(for: [TaskItem.self, Space.self, Session.self], inMemory: true)
}
