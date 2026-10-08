import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppStorageKey.defaultRepeatInterval) private var defaultRepeatInterval: RepeatInterval = .every15min
    @State private var isTestScheduled = false

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
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }

    private func scheduleTestNotification() {
        let reminder = Reminder(
            title: "Test de notification",
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
