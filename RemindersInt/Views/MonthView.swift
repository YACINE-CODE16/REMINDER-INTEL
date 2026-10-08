import SwiftUI
import SwiftData

struct MonthView: View {
    @Binding var selectedDate: Date
    var onShowDay: () -> Void
    /// The detail sheet is owned by the root view, so a deep link can close it.
    var onSelect: (Reminder) -> Void

    @Query(sort: \Reminder.dueDate) private var reminders: [Reminder]
    @State private var displayedMonth: Date

    private let calendar = Calendar.app

    init(selectedDate: Binding<Date>, onShowDay: @escaping () -> Void, onSelect: @escaping (Reminder) -> Void) {
        _selectedDate = selectedDate
        self.onShowDay = onShowDay
        self.onSelect = onSelect
        _displayedMonth = State(initialValue: Calendar.app.startOfMonth(for: selectedDate.wrappedValue))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                GlassCard(cornerRadius: 28) {
                    monthGrid
                }
                selectedDaySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CALENDRIER")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                Text(displayedMonth.formatted(.dateTime.month(.wide).year().locale(.app)).capitalized(with: .app))
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.text)
                    .contentTransition(.numericText())
            }
            Spacer()
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    monthButton(systemImage: "chevron.left", label: "Mois précédent", offset: -1)
                    monthButton(systemImage: "chevron.right", label: "Mois suivant", offset: 1)
                }
            }
        }
    }

    private func monthButton(systemImage: String, label: String, offset: Int) -> some View {
        Button {
            withAnimation(.snappy) {
                displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
            }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Palette.text)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    // MARK: - Grid

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    /// Days of the displayed month, padded with nil for the leading empty cells.
    private var monthDays: [Date?] {
        let range = calendar.range(of: .day, in: .month, for: displayedMonth) ?? 1..<31
        let weekday = calendar.component(.weekday, from: displayedMonth)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let days = range.map { calendar.date(byAdding: .day, value: $0 - 1, to: displayedMonth) }
        return Array(repeating: nil, count: leading) + days
    }

    private var daysWithReminders: Set<Date> {
        Set(reminders.map { calendar.startOfDay(for: $0.dueDate) })
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let markedDays = daysWithReminders

        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            }
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day, hasReminders: markedDays.contains(calendar.startOfDay(for: day)))
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ day: Date, hasReminders: Bool) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)

        return Button {
            withAnimation(.snappy) { selectedDate = day }
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day().locale(.app)))
                    .font(.callout.weight(isSelected || isToday ? .bold : .regular))
                    .foregroundStyle(isSelected ? .white : (isToday ? Palette.green : Palette.text))
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected {
                            Circle().fill(Palette.text)
                        }
                    }
                Circle()
                    .fill(hasReminders ? Palette.green : .clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected day

    private var selectedDayReminders: [Reminder] {
        reminders.filter { calendar.isDate($0.dueDate, inSameDayAs: selectedDate) }
    }

    private var selectedDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.app)).capitalized(with: .app))
                    .font(.title3.bold())
                    .foregroundStyle(Palette.text)
                Spacer()
                Button("Voir la journée", action: onShowDay)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.green)
            }

            if selectedDayReminders.isEmpty {
                Text("Aucun rappel ce jour")
                    .font(.callout)
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(selectedDayReminders) { reminder in
                    Button {
                        onSelect(reminder)
                    } label: {
                        ReminderCard(reminder: reminder)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    MonthView(selectedDate: .constant(.now), onShowDay: {}, onSelect: { _ in })
        .background(AppBackground())
        .modelContainer(for: Reminder.self, inMemory: true)
}
