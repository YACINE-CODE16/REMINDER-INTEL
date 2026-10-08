import SwiftUI

enum AppTab: CaseIterable, Identifiable {
    case day
    case month
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Jour"
        case .month: "Mois"
        case .settings: "Réglages"
        }
    }

    var systemImage: String {
        switch self {
        case .day: "list.bullet"
        case .month: "calendar"
        case .settings: "gearshape"
        }
    }
}

/// Floating glass tab bar with the green microphone button on the right.
struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    var onMicrophone: () -> Void
    var onManualEntry: () -> Void

    @Namespace private var namespace
    @State private var longPressCount = 0

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(AppTab.allCases) { tab in
                        tabButton(tab)
                    }
                }
                .padding(6)
                .glassEffect(.regular.interactive(), in: .capsule)

                // Tap: voice capture. Long press: manual form.
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .contentShape(.circle)
                    .glassEffect(.regular.tint(Palette.green).interactive(), in: .circle)
                    .onTapGesture(perform: onMicrophone)
                    .onLongPressGesture(minimumDuration: 0.5) {
                        longPressCount += 1
                        onManualEntry()
                    }
                    .sensoryFeedback(.impact, trigger: longPressCount)
                    .accessibilityElement()
                    .accessibilityLabel("Dicter un rappel")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(.default, onMicrophone)
                    .accessibilityAction(named: "Saisie manuelle", onManualEntry)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.snappy) { selectedTab = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Palette.text : Palette.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Palette.text.opacity(0.08))
                        .matchedGeometryEffect(id: "selectedTab", in: namespace)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}
