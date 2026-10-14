import SwiftUI
import SwiftData

struct TaskDetailView: View {
    let item: TaskItem

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var shouldDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let space = item.space {
                            Label(space.displayPath, systemImage: space.sfSymbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(space.color)
                        }
                        Text(item.title)
                            .font(.largeTitle.bold())
                            .foregroundStyle(Palette.text)
                            .strikethrough(item.status == .cancelled)
                    }

                    GlassCard {
                        VStack(spacing: 14) {
                            detailRow("Type", item.isReminder ? "Rappel" : "Tâche")
                            Divider()
                            if let dueDate = item.dueDate {
                                detailRow("Date", dueDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(.app)))
                                Divider()
                                detailRow("Heure", dueDate.formatted(.dateTime.hour().minute().locale(.app)))
                            } else {
                                detailRow("Échéance", "Sans date")
                            }
                            if item.isReminder {
                                Divider()
                                detailRow("Relance", item.repeatInterval.label)
                                Divider()
                                detailRow("Notifications envoyées", "\(item.remindersSent)")
                            }
                            Divider()
                            detailRow("Espace", item.space?.displayPath ?? "Aucun")
                            Divider()
                            detailRow("Statut", item.status.label)
                        }
                    }

                    if let note = item.note, !note.isEmpty {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Note")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.secondary)
                                Text(note)
                                    .foregroundStyle(Palette.text)
                            }
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
                TaskFormView(item: item)
            }
            .confirmationDialog("Supprimer ce rappel ?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    shouldDelete = true
                    dismiss()
                }
                Button("Garder", role: .cancel) {}
            } message: {
                Text("L'élément et ses notifications seront supprimés.")
            }
        }
        // Delete once the sheet is gone, so the view never renders a deleted model.
        .onDisappear {
            if shouldDelete { NotificationService.shared.delete(item) }
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
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    statusButton("Annuler", systemImage: "xmark", color: Palette.red, status: .cancelled)
                    statusButton("Fait", systemImage: "checkmark", color: Palette.green, status: .done)
                }
            }
            Button("Supprimer") { isConfirmingDelete = true }
                .font(.subheadline)
                .foregroundStyle(Palette.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func statusButton(_ title: String, systemImage: String, color: Color, status: ReminderStatus) -> some View {
        Button {
            withAnimation(.appSpring) { NotificationService.shared.setStatus(status, for: item) }
            dismiss()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(color).interactive(), in: .rect(cornerRadius: 16))
        .glassRim(.rect(cornerRadius: 16), opacity: 0.5)
    }
}
