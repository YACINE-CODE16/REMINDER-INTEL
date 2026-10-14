import SwiftUI
import SwiftData

/// Square colour badge with the space symbol in white.
struct SpaceBadge: View {
    let colorHex: String
    let symbol: String
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hexString: colorHex), in: .rect(cornerRadius: size * 0.325))
            .accessibilityHidden(true)
    }
}

extension SpaceBadge {
    init(space: Space, size: CGFloat = 40) {
        self.init(colorHex: space.colorHex, symbol: space.sfSymbol, size: size)
    }
}

/// "Aucun" plus every active space, indented by depth.
struct SpaceChoiceList: View {
    var selectedID: UUID?
    /// False where a space is required (sessions).
    var allowsNone = true
    var onSelect: (Space?) -> Void

    @Query private var spaces: [Space]

    var body: some View {
        List {
            if allowsNone {
                choiceRow(label: "Aucun", depth: 0, isSelected: selectedID == nil) {
                    Image(systemName: "tray")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 28, height: 28)
                        .background(Palette.text.opacity(0.06), in: .rect(cornerRadius: 9))
                } action: {
                    onSelect(nil)
                }
            }
            ForEach(Space.roots(of: spaces).flatMap(\.subtree)) { space in
                choiceRow(label: space.name, depth: space.pathComponents.count - 1, isSelected: space.id == selectedID) {
                    SpaceBadge(space: space, size: 28)
                } action: {
                    onSelect(space)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
    }

    private func choiceRow(
        label: String,
        depth: Int,
        isSelected: Bool,
        @ViewBuilder badge: () -> some View,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                badge()
                Text(label)
                    .foregroundStyle(Palette.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.green)
                }
            }
            .padding(.leading, CGFloat(depth) * 22)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.white.opacity(0.7))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Form row that pushes the space list.
struct SpacePickerRow: View {
    @Binding var selection: Space?
    var title = "Espace"
    var allowsNone = true

    var body: some View {
        NavigationLink {
            SpaceChoiceDestination(selection: $selection, title: title, allowsNone: allowsNone)
        } label: {
            LabeledContent(title) {
                Text(selection?.displayPath ?? (allowsNone ? "Aucun" : "À choisir"))
                    .foregroundStyle(selection?.color ?? Palette.secondary)
            }
        }
    }
}

private struct SpaceChoiceDestination: View {
    @Binding var selection: Space?
    let title: String
    let allowsNone: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SpaceChoiceList(selectedID: selection?.id, allowsNone: allowsNone) { space in
            selection = space
            dismiss()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Space list in a sheet: "Changer" on the capture toast, "Autre" when starting a session.
struct SpacePickerSheet: View {
    var title = "Changer d'espace"
    var selectedID: UUID?
    var allowsNone = true
    var onPick: (Space?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SpaceChoiceList(selectedID: selectedID, allowsNone: allowsNone) { space in
                onPick(space)
                dismiss()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
