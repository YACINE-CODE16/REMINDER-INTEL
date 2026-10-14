import SwiftUI
import SwiftData

/// New space: name, one of 8 colours, one of 12 symbols, optional parent.
struct SpaceFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorHex = SpaceStyle.colors[0]
    @State private var symbol = SpaceStyle.symbols[0]
    @State private var parent: Space?
    @FocusState private var isNameFocused: Bool

    private static let rowBackground = Color.white.opacity(0.7)

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        SpaceBadge(colorHex: colorHex, symbol: symbol, size: 44)
                        TextField("Nom", text: $name)
                            .font(.headline)
                            .focused($isNameFocused)
                    }
                    SpacePickerRow(selection: $parent, title: "Parent")
                }
                .listRowBackground(Self.rowBackground)

                Section("Couleur") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(SpaceStyle.colors, id: \.self) { hex in
                            Button {
                                colorHex = hex
                            } label: {
                                Circle()
                                    .fill(Color(hexString: hex))
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if hex == colorHex {
                                            Circle().strokeBorder(.white, lineWidth: 3)
                                            Circle().strokeBorder(Palette.text.opacity(0.25), lineWidth: 1)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Couleur \(hex)")
                            .accessibilityAddTraits(hex == colorHex ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Self.rowBackground)

                Section("Icône") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(SpaceStyle.symbols, id: \.self) { candidate in
                            Button {
                                symbol = candidate
                            } label: {
                                Image(systemName: candidate)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(candidate == symbol ? .white : Palette.text)
                                    .frame(width: 40, height: 40)
                                    .background(
                                        candidate == symbol ? Color(hexString: colorHex) : Palette.text.opacity(0.06),
                                        in: .rect(cornerRadius: 13)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(candidate)
                            .accessibilityAddTraits(candidate == symbol ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Self.rowBackground)
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Nouvel espace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer", role: .confirm) { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .onAppear { isNameFocused = true }
        }
    }

    private func save() {
        let siblings: [Space]
        if let parent {
            siblings = parent.children
        } else {
            siblings = (try? modelContext.fetch(FetchDescriptor<Space>()))?.filter { $0.parent == nil } ?? []
        }
        let space = Space(
            name: trimmedName,
            colorHex: colorHex,
            sfSymbol: symbol,
            sortOrder: (siblings.map(\.sortOrder).max() ?? -1) + 1,
            parent: parent
        )
        modelContext.insert(space)
        try? modelContext.save()
        dismiss()
    }
}
