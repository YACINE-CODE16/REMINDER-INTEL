import Charts
import SwiftUI
import SwiftData

/// Statistics: time per root space (ring), per day (stacked bars), streak and objectives tiles.
struct StatsView: View {
    enum Range: String, CaseIterable, Identifiable {
        case week = "7 jours"
        case month = "30 jours"
        var id: Self { self }
    }

    @Query(sort: \Session.startedAt) private var sessions: [Session]
    @State private var range: Range = .week

    private let calendar = Calendar.app

    /// This week (Monday to Sunday) or the last 30 days, today included.
    private func interval(now: Date) -> DateInterval {
        switch range {
        case .week:
            return TimeTotals.week(containing: now)
        case .month:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            let start = calendar.date(byAdding: .day, value: -30, to: tomorrow) ?? now
            return DateInterval(start: start, end: tomorrow)
        }
    }

    private var rangeLabel: String { range == .week ? "cette semaine" : "sur 30 jours" }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let period = interval(now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Statistiques")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Palette.text)
                    rangePicker
                    ringCard(period: period, now: now)
                    dailyCard(period: period, now: now)
                    HStack(spacing: 12) {
                        streakTile(now: now)
                        objectivesTile
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Range

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(Range.allCases) { option in
                Button {
                    withAnimation(.appSpring) { range = option }
                } label: {
                    Text(option.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(range == option ? .white : Palette.text)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background {
                            if range == option {
                                Capsule().fill(Palette.text)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(range == option ? .isSelected : [])
            }
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassRim(.capsule)
    }

    // MARK: - Ring

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let color: Color
        let seconds: TimeInterval
    }

    /// Top 4 root spaces, the rest grouped in "Autres".
    private func slices(period: DateInterval, now: Date) -> [Slice] {
        let roots = TimeTotals.byRoot(sessions, in: period, now: now)
        var result = roots.prefix(roots.count > 5 ? 4 : 5).map {
            Slice(id: $0.space.id.uuidString, name: $0.space.name, color: $0.space.color, seconds: $0.seconds)
        }
        if roots.count > 5 {
            let others = roots.dropFirst(4).reduce(0) { $0 + $1.seconds }
            result.append(Slice(id: "others", name: "Autres", color: Palette.secondary.opacity(0.5), seconds: others))
        }
        return result
    }

    private func ringCard(period: DateInterval, now: Date) -> some View {
        let parts = slices(period: period, now: now)
        let total = parts.reduce(0) { $0 + $1.seconds }
        return GlassCard(cornerRadius: 28, padding: 18) {
            HStack(spacing: 22) {
                ZStack {
                    if parts.isEmpty {
                        Circle()
                            .stroke(Palette.text.opacity(0.07), lineWidth: 16)
                            .padding(8)
                    } else {
                        Chart(parts) { slice in
                            SectorMark(
                                angle: .value("Temps", slice.seconds),
                                innerRadius: .ratio(0.733),
                                angularInset: 1.5
                            )
                            .cornerRadius(3)
                            .foregroundStyle(slice.color)
                        }
                        .chartLegend(.hidden)
                    }
                    VStack(spacing: 0) {
                        Text(TimeFormat.short(total))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Palette.text)
                            .minimumScaleFactor(0.7)
                        Text(rangeLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondary)
                    }
                }
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 8) {
                    if parts.isEmpty {
                        Text("Aucune session")
                            .font(.subheadline)
                            .foregroundStyle(Palette.secondary)
                    }
                    ForEach(parts) { slice in
                        HStack(spacing: 8) {
                            Circle().fill(slice.color).frame(width: 9, height: 9)
                            Text(slice.name)
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.text)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(TimeFormat.short(slice.seconds))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Palette.text)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Per day

    private struct DayBar: Identifiable {
        let id: Date
        let isToday: Bool
        let isFuture: Bool
        let segments: [(color: Color, seconds: TimeInterval)]
        var total: TimeInterval { segments.reduce(0) { $0 + $1.seconds } }
    }

    private func days(period: DateInterval, now: Date) -> [DayBar] {
        var result: [DayBar] = []
        var day = period.start
        while day < period.end {
            let interval = TimeTotals.day(containing: day)
            let roots = TimeTotals.byRoot(sessions, in: interval, now: now)
            result.append(DayBar(
                id: day,
                isToday: calendar.isDate(day, inSameDayAs: now),
                isFuture: day > now,
                segments: roots.map { ($0.space.color, $0.seconds) }
            ))
            day = interval.end
        }
        return result
    }

    private func dailyCard(period: DateInterval, now: Date) -> some View {
        let bars = days(period: period, now: now)
        let elapsed = max(1, bars.filter { !$0.isFuture }.count)
        let average = bars.reduce(0) { $0 + $1.total } / Double(elapsed)
        let maximum = max(bars.map(\.total).max() ?? 0, 3600)
        return GlassCard(cornerRadius: 28, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Par jour")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.text)
                    Spacer()
                    Text("moy. \(TimeFormat.short(average))")
                        .font(.subheadline)
                        .foregroundStyle(Palette.secondary)
                }
                HStack(alignment: .bottom, spacing: range == .week ? 10 : 3) {
                    ForEach(bars) { bar in
                        VStack(spacing: 6) {
                            stackedBar(bar, maximum: maximum)
                                .frame(height: 110)
                            Text(dayLabel(bar.id))
                                .font(.system(size: 11, weight: bar.isToday ? .bold : .regular))
                                .foregroundStyle(bar.isToday ? Palette.text : Palette.secondary)
                                .frame(height: 13)
                        }
                    }
                }
            }
        }
    }

    private func stackedBar(_ bar: DayBar, maximum: TimeInterval) -> some View {
        GeometryReader { proxy in
            let height = proxy.size.height * min(bar.total / maximum, 1)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    ForEach(Array(bar.segments.enumerated()), id: \.offset) { _, segment in
                        Rectangle()
                            .fill(segment.color)
                            .frame(height: height * segment.seconds / max(bar.total, 1))
                    }
                }
                .clipShape(.rect(cornerRadius: range == .week ? 6 : 3))
            }
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: range == .week ? 6 : 3)
                    .fill(Palette.text.opacity(0.05))
            }
            .overlay {
                if bar.isToday {
                    RoundedRectangle(cornerRadius: range == .week ? 6 : 3)
                        .strokeBorder(Palette.text.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(dayLabel(bar.id)) : \(TimeFormat.short(bar.total))")
    }

    /// "L M M J V S D" for the week; every 5th day number over 30 days.
    private func dayLabel(_ day: Date) -> String {
        if range == .week {
            return String(day.formatted(.dateTime.weekday(.narrow).locale(.app)))
        }
        let number = calendar.component(.day, from: day)
        return number % 5 == 0 || calendar.isDateInToday(day) ? "\(number)" : ""
    }

    // MARK: - Tiles

    /// Longest current run of consecutive days (today or up to yesterday) per root space.
    private func bestStreak(now: Date) -> (space: Space, current: Int, record: Int)? {
        var daysByRoot: [UUID: (Space, Set<Date>)] = [:]
        for session in sessions {
            guard let root = session.rootSpace else { continue }
            daysByRoot[root.id, default: (root, [])].1.insert(calendar.startOfDay(for: session.startedAt))
        }
        let today = calendar.startOfDay(for: now)
        var best: (Space, Int, Int)?
        for (space, days) in daysByRoot.values {
            var cursor = days.contains(today) ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
            var current = 0
            while days.contains(cursor) {
                current += 1
                cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            }
            var record = 0
            var run = 0
            var previous: Date?
            for day in days.sorted() {
                if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                    run += 1
                } else {
                    run = 1
                }
                record = max(record, run)
                previous = day
            }
            if current > (best?.1 ?? 0) { best = (space, current, record) }
        }
        return best.map { (space: $0.0, current: $0.1, record: $0.2) }
    }

    private func streakTile(now: Date) -> some View {
        let streak = bestStreak(now: now)
        return tile {
            Text("Série")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            if let streak {
                Text("\(streak.space.name) \(streak.current) j")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(streak.current >= streak.record ? "record personnel" : "record : \(streak.record) j")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.secondary)
                Text("aucune série en cours")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }

    /// Objectives arrive in step 6c.
    private var objectivesTile: some View {
        tile {
            Text("Objectifs atteints")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            Text("— / —")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.secondary)
            Text("avec les objectifs")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
        }
    }

    private func tile(@ViewBuilder content: () -> some View) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 3) {
                content()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
