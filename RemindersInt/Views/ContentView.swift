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
    #if DEBUG
    @State private var debugDictation: String?
    #endif

    private let notifications = NotificationService.shared
    private let tracking = TrackingService.shared
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
        .sheet(item: $detailItem) { item in
            TaskDetailView(item: item)
        }
        .task {
            if !hasSeededDemoData {
                DemoData.insert(into: modelContext)
                try? modelContext.save()
                hasSeededDemoData = true
            }
            #if DEBUG
            await applyDebugLaunchArguments()
            // Screenshots on a fresh simulator: no permission alert over the UI.
            if !UserDefaults.standard.bool(forKey: "uiNoPrompt") {
                await notifications.requestAuthorization()
            }
            #else
            await notifications.requestAuthorization()
            #endif
            await ParserService.shared.checkModel()
            // Safety net after a reinstall or a missed update.
            notifications.rescheduleAllPending()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            notifications.syncSentCounts()
            tracking.resume()
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
                        onChange: { isChangingSpace = true }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: captureOutcome.id) {
                        // Longer when a question is asked.
                        try? await Task.sleep(for: .seconds(captureOutcome.asksForSpace ? 10 : 6))
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
    /// `-seedDemoSessions YES` (two weeks of sessions, once), `-uiTab day|month|spaces|tracking|stats|settings`, `-uiSpace <name>` (opens that space),
    /// `-uiScreen capture|detail|form`, `-uiDictation "<phrase>"` (validated through the
    /// simulated dictation field), `-parserSelfTest YES` (prints the routing table).
    private func applyDebugLaunchArguments() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "seedDemoSessions") {
            DemoSessions.insert(into: modelContext)
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
