import SwiftUI
import SwiftData

struct DayView: View {
    @Binding var selectedDate: Date
    var onShowCalendar: () -> Void
    /// The detail sheet is owned by the root view, so a deep link can close it.
    var onSelect: (Reminder) -> Void

    @Query(sort: \Reminder.dueDate) private var reminders: [Reminder]
    @State private var reminderToDelete: Reminder?

    private let calendar = Calendar.app

    private var dayReminders: [Reminder] {
        reminders.filter { calendar.isDate($0.dueDate, inSameDayAs: selectedDate) }
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            daySelector
            reminderList
        }
        .padding(.top, 8)
    }

    // MARK: - Header

    private var dayTitle: String {
        if calendar.isDateInToday(selectedDate) { return "Aujourd'hui" }
        if calendar.isDateInTomorrow(selectedDate) { return "Demain" }
        if calendar.isDateInYesterday(selectedDate) { return "Hier" }
        return selectedDate.formatted(.dateTime.weekday(.wide).locale(.app)).capitalized(with: .app)
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(.app)).uppercased())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                Text(dayTitle)
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.text)
            }
            Spacer()
            Button(action: onShowCalendar) {
                Image(systemName: "calendar")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Palette.text)
                    .frame(width: 48, height: 48)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassRim(.circle)
            .accessibilityLabel("Calendrier")
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Day selector

    private var daySelector: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(-2...2, id: \.self) { offset in
                    dayButton(calendar.date(byAdding: .day, value: offset, to: selectedDate) ?? selectedDate)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func dayButton(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let hasReminders = reminders.contains { calendar.isDate($0.dueDate, inSameDayAs: day) }
        let shape = RoundedRectangle(cornerRadius: 20)

        return Button {
            withAnimation(.appSpring) { selectedDate = calendar.startOfDay(for: day) }
        } label: {
            VStack(spacing: 4) {
                Text(day.formatted(.dateTime.weekday(.abbreviated).locale(.app)).uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : Palette.secondary)
                Text(day.formatted(.dateTime.day().locale(.app)))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(isSelected ? .white : (isToday ? Palette.green : Palette.text))
                Circle()
                    .fill(hasReminders ? Palette.green : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                shape
                    .fill(Palette.text)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
        }
        .glassEffect(isSelected ? .identity : .regular.tint(.white.opacity(0.55)).interactive(), in: shape)
        .glassRim(shape, opacity: isSelected ? 0 : 0.9)
    }

    // MARK: - List

    private var reminderList: some View {
        List {
            if dayReminders.isEmpty {
                Text("Aucun rappel ce jour")
                    .font(.callout)
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            ForEach(dayReminders) { reminder in
                Button {
                    onSelect(reminder)
                } label: {
                    ReminderCard(reminder: reminder)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 20, bottom: 6, trailing: 20))
                // Swipe left: full swipe deletes (after confirmation), partial swipe also shows Done.
                // No destructive role, so the row stays in place until the deletion is confirmed.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button {
                        reminderToDelete = reminder
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                    .tint(Palette.red)

                    Button {
                        setStatus(.done, for: reminder)
                    } label: {
                        Label("Fait", systemImage: "checkmark")
                    }
                    .tint(Palette.green)
                }
                // Swipe right: cancelled.
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        setStatus(.cancelled, for: reminder)
                    } label: {
                        Label("Annuler", systemImage: "xmark")
                    }
                    .tint(Palette.red)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Room for the first card's shadow, which the list would otherwise clip.
        .contentMargins(.top, 10, for: .scrollContent)
        .confirmationDialog(
            "Supprimer ce rappel ?",
            isPresented: Binding(
                get: { reminderToDelete != nil },
                set: { if !$0 { reminderToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: reminderToDelete
        ) { reminder in
            Button("Supprimer", role: .destructive) {
                withAnimation(.appSpring) { NotificationService.shared.delete(reminder) }
            }
            Button("Garder", role: .cancel) {}
        } message: { reminder in
            Text("« \(reminder.title) » et ses notifications seront supprimés.")
        }
    }

    private func setStatus(_ status: ReminderStatus, for reminder: Reminder) {
        withAnimation(.appSpring) { NotificationService.shared.setStatus(status, for: reminder) }
    }
}

#Preview {
    DayView(selectedDate: .constant(.now), onShowCalendar: {}, onSelect: { _ in })
        .background(AppBackground())
        .modelContainer(for: Reminder.self, inMemory: true)
}
