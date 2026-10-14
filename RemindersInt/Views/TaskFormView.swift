import SwiftUI
import SwiftData

/// Add / edit form, presented in a sheet.
struct TaskFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let item: TaskItem?
    private let rawTranscript: String?

    @State private var title: String
    @State private var isReminder: Bool
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var repeatInterval: RepeatInterval
    @State private var space: Space?
    @State private var note: String
    @FocusState private var isTitleFocused: Bool

    /// Edit an existing task.
    init(item: TaskItem) {
        self.item = item
        self.rawTranscript = nil
        _title = State(initialValue: item.title)
        _isReminder = State(initialValue: item.isReminder)
        _hasDueDate = State(initialValue: item.dueDate != nil)
        _dueDate = State(initialValue: item.dueDate ?? Self.suggestedDueDate(on: .now))
        _repeatInterval = State(initialValue: item.repeatInterval)
        _space = State(initialValue: item.space)
        _note = State(initialValue: item.note ?? "")
    }

    /// Create a new task, optionally pre-filled from a dictation or filed in a space.
    init(
        initialDate: Date,
        repeatInterval: RepeatInterval,
        title: String = "",
        rawTranscript: String? = nil,
        isReminder: Bool = true,
        hasDueDate: Bool = true,
        space: Space? = nil
    ) {
        self.item = nil
        self.rawTranscript = rawTranscript
        _title = State(initialValue: title)
        _isReminder = State(initialValue: isReminder)
        _hasDueDate = State(initialValue: hasDueDate)
        _dueDate = State(initialValue: initialDate)
        _repeatInterval = State(initialValue: repeatInterval)
        _space = State(initialValue: space)
        _note = State(initialValue: "")
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

    /// White translucent rows so the halos of the background show through, like the glass cards.
    private static let rowBackground = Color.white.opacity(0.7)

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A reminder always needs a date: its follow-ups start from it.
    private var isDated: Bool { isReminder || hasDueDate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre", text: $title, axis: .vertical)
                        .focused($isTitleFocused)
                    SpacePickerRow(selection: $space)
                }
                .listRowBackground(Self.rowBackground)

                Section {
                    Toggle("Rappel avec relances", isOn: $isReminder.animation(.appSpring))
                    if !isReminder {
                        Toggle("Échéance", isOn: $hasDueDate.animation(.appSpring))
                    }
                    if isDated {
                        DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                        DatePicker("Heure", selection: $dueDate, displayedComponents: .hourAndMinute)
                    }
                }
                .listRowBackground(Self.rowBackground)

                if isReminder {
                    Section {
                        Picker("Relance", selection: $repeatInterval) {
                            ForEach(RepeatInterval.allCases) { interval in
                                Text(interval.label).tag(interval)
                            }
                        }
                    }
                    .listRowBackground(Self.rowBackground)
                }

                Section("Note") {
                    TextField("Facultative", text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
                .listRowBackground(Self.rowBackground)
            }
            .tint(Palette.green)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(item == nil ? "Nouvelle tâche" : "Modifier")
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
                if item == nil, title.isEmpty { isTitleFocused = true }
            }
        }
    }

    private func save() {
        let date = isDated ? Self.truncatedToMinute(dueDate) : nil
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved: TaskItem
        if let item {
            item.title = trimmedTitle
            item.dueDate = date
            item.isReminder = isReminder
            item.repeatInterval = isReminder ? repeatInterval : .none
            item.space = space
            item.note = trimmedNote.isEmpty ? nil : trimmedNote
            saved = item
        } else {
            saved = TaskItem(
                title: trimmedTitle,
                dueDate: date,
                repeatInterval: isReminder ? repeatInterval : .none,
                rawTranscript: rawTranscript,
                note: trimmedNote.isEmpty ? nil : trimmedNote,
                isReminder: isReminder,
                space: space
            )
            modelContext.insert(saved)
        }
        try? modelContext.save()
        NotificationService.shared.schedule(saved)
        dismiss()
    }
}

#Preview {
    TaskFormView(initialDate: .now, repeatInterval: .every15min)
        .modelContainer(for: [TaskItem.self, Space.self], inMemory: true)
}
