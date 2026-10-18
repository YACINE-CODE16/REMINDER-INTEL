import SwiftUI

/// GitHub-style activity grid: one column per week (oldest on the left), one row per weekday
/// (Monday on top), month labels underneath. Each day is tinted by its value (0...1) in five
/// steps; days without a value use the lightest step, days after today are not drawn.
struct ContributionGrid: View {
    /// Start of day → 0...1.
    var values: [Date: Double]
    var color: Color
    var weeks: Int = 20
    var cellSize: CGFloat = 12
    var spacing: CGFloat = 3
    var today: Date = .now

    private var calendar: Calendar { .app }

    /// Opacity steps: 0, up to 2/5, 3/5, 4/5, full.
    static func opacity(for value: Double) -> Double {
        switch value {
        case ..<0.01: 0.08
        case ..<0.41: 0.3
        case ..<0.61: 0.55
        case ..<0.81: 0.8
        default: 1
        }
    }

    /// Monday of each displayed week.
    private var weekStarts: [Date] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? calendar.startOfDay(for: today)
        return (0..<weeks).reversed().compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
    }

    var body: some View {
        let starts = weekStarts
        let lastDay = calendar.startOfDay(for: today)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(starts, id: \.self) { weekStart in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { offset in
                            let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(Self.opacity(for: values[day] ?? 0)))
                                .frame(width: cellSize, height: cellSize)
                                .opacity(day > lastDay ? 0 : 1)
                        }
                    }
                }
            }
            monthLabels(starts)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Month name under the first week starting in that month.
    private func monthLabels(_ starts: [Date]) -> some View {
        let column = cellSize + spacing
        return ZStack(alignment: .topLeading) {
            ForEach(Array(starts.enumerated()), id: \.offset) { index, start in
                let previous = index > 0 ? calendar.component(.month, from: starts[index - 1]) : nil
                if previous != calendar.component(.month, from: start), index < starts.count - 1 || previous == nil {
                    Text(start.formatted(.dateTime.month(.abbreviated).locale(.app)))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .fixedSize()
                        .offset(x: CGFloat(index) * column)
                }
            }
        }
        .frame(width: CGFloat(starts.count) * column - spacing, height: 12, alignment: .topLeading)
    }

    private var accessibilitySummary: String {
        let shown = values.filter { $0.key <= today }
        let full = shown.values.filter { $0 >= 0.99 }.count
        return "\(weeks) dernières semaines, \(full) jours complets"
    }
}
