import SwiftUI
import SwiftData

/// Prayer module block at the top of the space detail: next prayer and streak, the five
/// prayers of the day, 20 weeks of history, prayers to make up and the most missed one.
struct PrayerModuleView: View {
    let settings: PrayerSettings
    var color: Color

    @Query private var records: [PrayerRecord]
    private let service = PrayerService.shared

    static let orange = Color(hex: 0xFF9F0A)

    var body: some View {
        // Times and states move with the clock; `revision` follows ticks and settings.
        let _ = service.revision
        TimelineView(.everyMinute) { context in
            let now = context.date
            let today = Calendar.app.startOfDay(for: now)
            let slots = service.slots(on: today, settings: settings, records: records, now: now)
            let stats = service.stats(settings: settings, records: records, now: now)
            VStack(spacing: 14) {
                nextCard(now: now, streak: stats.streak)
                listCard(slots)
                gridCard(stats, now: now)
                HStack(spacing: 12) {
                    makeUpTile(stats)
                    mostMissedTile(stats)
                }
            }
        }
    }

    // MARK: - Next prayer

    private func nextCard(now: Date, streak: Int) -> some View {
        let next = service.nextPrayer(after: now, settings: settings)
        let name = next.map { $0.prayer.name(on: $0.day, calendar: .app) } ?? "—"
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PROCHAINE · \(name.uppercased())")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(next.map { $0.time.formatted(.dateTime.hour().minute().locale(.app)) } ?? "--:--")
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                if let next {
                    Text(Self.countdown(from: now, to: next.time))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("SÉRIE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(streak) j")
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
        }
        .padding(18)
        .background(Palette.text, in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
        .accessibilityElement(children: .combine)
    }

    /// "dans 24 min", "dans 1 h 24".
    static func countdown(from now: Date, to date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        guard minutes >= 60 else { return "dans \(minutes) min" }
        return "dans \(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    // MARK: - Five prayers

    private func listCard(_ slots: [PrayerSlot]) -> some View {
        GlassCard(padding: 6) {
            VStack(spacing: 0) {
                ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                    if index > 0 {
                        Divider().padding(.leading, 52)
                    }
                    PrayerRow(slot: slot, color: color)
                }
            }
        }
    }

    // MARK: - History

    private func gridCard(_ stats: PrayerService.Stats, now: Date) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("20 dernières semaines")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Spacer(minLength: 8)
                    if let ratio = stats.monthRatio {
                        Text("\(Int((ratio * 100).rounded())) % ce mois")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(color)
                    }
                }
                ContributionGrid(values: stats.dailyValues, color: color, weeks: 20, today: now)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Tiles

    private func makeUpTile(_ stats: PrayerService.Stats) -> some View {
        let parts = Prayer.allCases.compactMap { prayer -> String? in
            guard let count = stats.toMakeUp[prayer], count > 0 else { return nil }
            return "\(count) \(prayer.name)"
        }
        return tile {
            Text("À rattraper")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            Text("\(stats.toMakeUpTotal)")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(stats.toMakeUpTotal > 0 ? Self.orange : Palette.text)
            Text(parts.isEmpty ? "rien en retard" : parts.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func mostMissedTile(_ stats: PrayerService.Stats) -> some View {
        tile {
            Text("La plus ratée")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.secondary)
            Text(stats.mostMissed?.prayer.name ?? "—")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Palette.text)
            Text(stats.mostMissed.map { "\(Int(($0.onTimeRatio * 100).rounded())) % à l'heure" } ?? "pas encore de données")
                .font(.system(size: 12))
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
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

/// One prayer: state circle (tap = tick / untick, missed = made up), name, time, state.
struct PrayerRow: View {
    let slot: PrayerSlot
    var color: Color

    private let service = PrayerService.shared

    private var stateLabel: (text: String, color: Color) {
        switch slot.state {
        case .onTime: ("À l'heure", Palette.green)
        case .late: ("En retard", PrayerModuleView.orange)
        case .madeUp: ("Rattrapée", Palette.secondary)
        case .missed: ("Manquée", Palette.red)
        case .toDo: ("À faire", color)
        case .next: ("Prochaine", color)
        case .upcoming: ("À venir", Palette.secondary)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: toggle) {
                circle
                    .frame(width: 26, height: 26)
                    .frame(width: 40, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(slot.state.isDone ? "Décocher \(slot.name)" : "Cocher \(slot.name)")

            VStack(alignment: .leading, spacing: 1) {
                Text(slot.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.text)
                Text(slot.time.formatted(.dateTime.hour().minute().locale(.app)))
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 8)
            Text(stateLabel.text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(stateLabel.color)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.trailing, 6)
        .contentShape(.rect)
        .contextMenu {
            Button("À l'heure", systemImage: "checkmark.circle") {
                withAnimation(.appSpring) { _ = service.check(slot.prayer, on: slot.day, mark: .onTime) }
            }
            Button("En retard", systemImage: "clock.badge.exclamationmark") {
                withAnimation(.appSpring) { _ = service.check(slot.prayer, on: slot.day, mark: .late) }
            }
            Button("Rattrapée", systemImage: "arrow.uturn.backward.circle") {
                withAnimation(.appSpring) { _ = service.check(slot.prayer, on: slot.day, mark: .madeUp) }
            }
            if slot.state.isDone {
                Button("Non faite", systemImage: "circle", role: .destructive) {
                    withAnimation(.appSpring) { service.uncheck(slot.prayer, on: slot.day) }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(stateLabel.text)
    }

    @ViewBuilder
    private var circle: some View {
        switch slot.state {
        case .onTime, .late, .madeUp:
            ZStack {
                Circle().fill(slot.state == .onTime ? Palette.green : slot.state == .late ? PrayerModuleView.orange : Palette.secondary.opacity(0.6))
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        case .missed:
            Circle().strokeBorder(Palette.red, lineWidth: 2)
        case .toDo:
            Circle()
                .fill(color.opacity(0.15))
                .overlay { Circle().strokeBorder(color, lineWidth: 2) }
        case .next:
            Circle().strokeBorder(color, lineWidth: 2)
        case .upcoming:
            Circle().strokeBorder(Palette.secondary.opacity(0.4), lineWidth: 1.5)
        }
    }

    private func toggle() {
        withAnimation(.appSpring) {
            if slot.state.isDone {
                service.uncheck(slot.prayer, on: slot.day)
            } else {
                // A missed prayer ticked now is made up (automatic in `check`).
                _ = service.check(slot.prayer, on: slot.day)
            }
        }
    }
}
