import SwiftUI
import SwiftData

/// Add / edit form, presented in a sheet.
struct ReminderFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let reminder: Reminder?
    private let rawTranscript: String?

    @State private var title: String
    @State private var dueDate: Date
    @State private var repeatInterval: RepeatInterval
    @FocusState private var isTitleFocused: Bool

    /// Edit an existing reminder.
    init(reminder: Reminder) {
        self.reminder = reminder
        self.rawTranscript = nil
        _title = State(initialValue: reminder.title)
        _dueDate = State(initialValue: reminder.dueDate)
        _repeatInterval = State(initialValue: reminder.repeatInterval)
    }

    /// Create a new reminder, optionally pre-filled from a dictation without a date.
    init(initialDate: Date, repeatInterval: RepeatInterval, title: String = "", rawTranscript: String? = nil) {
        self.reminder = nil
        self.rawTranscript = rawTranscript
        _title = State(initialValue: title)
        _dueDate = State(initialValue: initialDate)
        _repeatInterval = State(initialValue: repeatInterval)
    }

    /// Today: next quarter hour at least one hour from now. Other days: 9:00.
    static func suggestedDueDate(on day: Date, now: Date = .now) -> Date {
        let calendar = Calendar.app
        guard calendar.isDate(day, inSameDayAs: now) else {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        let inOneHour = now.addingTimeInterval(3600)
        let minute = calendar.component(.minute, from: inOneHour)
        let roundUp = (15 - minute % 15) % 15
        let rounded = calendar.date(byAdding: .minute, value: roundUp, to: inOneHour) ?? inOneHour
        return truncatedToMinute(rounded)
    }

    private static func truncatedToMinute(_ date: Date) -> Date {
        let calendar = Calendar.app
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: components) ?? date
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title, axis: .vertical)
                        .focused($isTitleFocused)
                }
                Section {
                    DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                    DatePicker("Heure", selection: $dueDate, displayedComponents: .hourAndMinute)
                }
                Section {
                    Picker("Relance", selection: $repeatInterval) {
                        ForEach(RepeatInterval.allCases) { interval in
                            Text(interval.label).tag(interval)
                        }
                    }
                }
            }
            .tint(Palette.green)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(reminder == nil ? "Nouveau rappel" : "Modifier le rappel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", role: .confirm) { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear {
                if reminder == nil, title.isEmpty { isTitleFocused = true }
            }
        }
    }

    private func save() {
        let date = Self.truncatedToMinute(dueDate)
        let saved: Reminder
        if let reminder {
            reminder.title = trimmedTitle
            reminder.dueDate = date
            reminder.repeatInterval = repeatInterval
            saved = reminder
        } else {
            saved = Reminder(title: trimmedTitle, dueDate: date, repeatInterval: repeatInterval, rawTranscript: rawTranscript)
            modelContext.insert(saved)
        }
        try? modelContext.save()
        NotificationService.shared.schedule(saved)
        dismiss()
    }
}

#Preview {
    ReminderFormView(initialDate: .now, repeatInterval: .every15min)
        .modelContainer(for: Reminder.self, inMemory: true)
}
