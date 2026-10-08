import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.defaultRepeatInterval) private var defaultRepeatInterval: RepeatInterval = .every15min
    @State private var isTestScheduled = false
    @State private var cleanupMessage: String?

    private static let testReminderTitle = "Test de notification"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Réglages")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Palette.text)
                    .padding(.bottom, 8)

                GlassCard {
                    HStack {
                        Text("Relance par défaut")
                            .foregroundStyle(Palette.text)
                        Spacer()
                        Picker("Relance par défaut", selection: $defaultRepeatInterval) {
                            ForEach(RepeatInterval.allCases) { interval in
                                Text(interval.label).tag(interval)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Palette.secondary)
                    }
                }

                Text("Appliquée aux nouveaux rappels.")
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 4)

                GlassCard {
                    Button(action: scheduleTestNotification) {
                        HStack {
                            Text("Tester une notification dans 10 s")
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Image(systemName: "bell.badge")
                                .foregroundStyle(Palette.green)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 12)

                if isTestScheduled {
                    Text("Rappel de test créé, relance toutes les 5 min. Marque-le Fait pour arrêter.")
                        .font(.footnote)
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 4)
                }

                GlassCard {
                    Button(action: completeTestReminders) {
                        HStack {
                            Text("Marquer tous les rappels de test comme faits")
                                .foregroundStyle(Palette.text)
                            Spacer()
                            Image(systemName: "checkmark.circle")
                                .foregroundStyle(Palette.green)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }

                if let cleanupMessage {
                    Text(cleanupMessage)
                        .font(.footnote)
                        .foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private func completeTestReminders() {
        let title = Self.testReminderTitle
        let descriptor = FetchDescriptor<Reminder>(predicate: #Predicate { $0.title == title })
        let pending = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status == .pending }
        for reminder in pending {
            NotificationService.shared.setStatus(.done, for: reminder)
        }
        cleanupMessage = switch pending.count {
        case 0: "Aucun rappel de test en cours."
        case 1: "1 rappel de test marqué comme fait."
        default: "\(pending.count) rappels de test marqués comme faits."
        }
    }

    private func scheduleTestNotification() {
        let reminder = Reminder(
            title: Self.testReminderTitle,
            dueDate: .now.addingTimeInterval(10),
            repeatInterval: .every5min
        )
        modelContext.insert(reminder)
        try? modelContext.save()
        NotificationService.shared.schedule(reminder)
        isTestScheduled = true
    }
}

#Preview {
    SettingsView()
        .background(AppBackground())
        .modelContainer(for: Reminder.self, inMemory: true)
}
