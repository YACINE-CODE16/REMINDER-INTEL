import SwiftUI
import SwiftData

/// Add or edit a session: space, day, start and end times, note.
/// An end earlier than the start means the session ran past midnight; it is split on save.
struct SessionFormView: View {
    @Environment(\.dismiss) private var dismiss

    private let session: Session?
    @State private var space: Space?
    @State private var day: Date
    @State private var start: Date
    @State private var end: Date
    @State private var note: String

    private static let rowBackground = Color.white.opacity(0.7)
    private let tracking = TrackingService.shared

    /// Edit an existing session.
    init(session: Session) {
        self.session = session
        _space = State(initialValue: session.space)
        _day = State(initialValue: session.startedAt)
        _start = State(initialValue: session.startedAt)
        _end = State(initialValue: session.endedAt ?? .now)
        _note = State(initialValue: session.note ?? "")
    }

    /// New past session: last hour by default.
    init(space: Space?) {
        self.session = nil
        let now = Date.now
        _space = State(initialValue: space)
        _day = State(initialValue: now)
        _start = State(initialValue: now.addingTimeInterval(-3600))
        _end = State(initialValue: now)
        _note = State(initialValue: "")
    }

    private var isActive: Bool { session?.isActive ?? false }

    /// Start and end on the chosen day; an end before the start moves to the next day.
    private var interval: (start: Date, end: Date) {
        let calendar = Calendar.app
        func combine(_ time: Date) -> Date {
            let parts = calendar.dateComponents([.hour, .minute], from: time)
            return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
        }
        let startDate = combine(start)
        var endDate = combine(end)
        if endDate <= startDate {
            endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        }
        return (startDate, endDate)
    }

    private var canSave: Bool {
        guard space != nil else { return false }
        return isActive ? interval.start <= .now : interval.end > interval.start
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SpacePickerRow(selection: $space, allowsNone: false)
                }
                .listRowBackground(Self.rowBackground)

                Section {
                    DatePicker("Jour", selection: $day, displayedComponents: .date)
                    DatePicker("Début", selection: $start, displayedComponents: .hourAndMinute)
                    if isActive {
                        LabeledContent("Fin", value: "En cours")
                    } else {
                        DatePicker("Fin", selection: $end, displayedComponents: .hourAndMinute)
                        LabeledContent("Durée", value: TimeFormat.short(interval.end.timeIntervalSince(interval.start)))
                    }
                } footer: {
                    if !isActive, !Calendar.app.isDate(interval.start, inSameDayAs: interval.end) {
                        Text("La session passe minuit : elle sera coupée en deux.")
                    }
                }
                .listRowBackground(Self.rowBackground)

                Section("Note") {
                    TextField("Facultative", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                .listRowBackground(Self.rowBackground)
            }
            .tint(Palette.green)
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(session == nil ? "Nouvelle session" : "Modifier la session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", role: .confirm) { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        guard let space else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = interval
        if let session {
            tracking.update(session, space: space, start: range.start, end: isActive ? nil : range.end, note: trimmed.isEmpty ? nil : trimmed)
        } else {
            tracking.log(in: space, from: range.start, to: range.end, note: trimmed.isEmpty ? nil : trimmed)
        }
        dismiss()
    }
}
