import SwiftUI
import SwiftData

struct ReminderDetailView: View {
    let reminder: Reminder

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(reminder.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Palette.text)
                        .strikethrough(reminder.status == .cancelled)

                    GlassCard {
                        VStack(spacing: 14) {
                            detailRow("Date", reminder.dueDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(.app)))
                            Divider()
                            detailRow("Heure", reminder.dueDate.formatted(.dateTime.hour().minute().locale(.app)))
                            Divider()
                            detailRow("Relance", reminder.repeatInterval.label)
                            Divider()
                            detailRow("Relances envoyées", "\(reminder.remindersSent)")
                            Divider()
                            detailRow("Statut", reminder.status.label)
                        }
                    }
                }
                .padding(20)
            }
            .background(AppBackground())
            .safeAreaInset(edge: .bottom) {
                actionButtons
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Modifier") { isEditing = true }
                }
            }
            .sheet(isPresented: $isEditing) {
                ReminderFormView(reminder: reminder)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(Palette.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(Palette.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private var actionButtons: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                statusButton("Annuler", systemImage: "xmark", color: Palette.red, status: .cancelled)
                statusButton("Fait", systemImage: "checkmark", color: Palette.green, status: .done)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func statusButton(_ title: String, systemImage: String, color: Color, status: ReminderStatus) -> some View {
        Button {
            NotificationService.shared.setStatus(status, for: reminder)
            dismiss()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(color).interactive(), in: .capsule)
    }
}
