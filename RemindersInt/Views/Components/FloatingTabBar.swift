import SwiftUI

enum AppTab: CaseIterable, Identifiable {
    case day
    case month
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .day: "Jour"
        case .month: "Calendrier"
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

    private static let height: CGFloat = 64

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases) { tab in
                        tabButton(tab)
                    }
                }
                .padding(6)
                .frame(height: Self.height)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassRim(.capsule)

                // Tap: voice capture. Long press: manual form.
                Image(systemName: "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Self.height, height: Self.height)
                    .contentShape(.circle)
                    .glassEffect(.regular.tint(Palette.green).interactive(), in: .circle)
                    .glassRim(.circle, opacity: 0.6)
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
        .shadow(color: .black.opacity(0.1), radius: 16, y: 12)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.appSpring) { selectedTab = tab }
        } label: {
            Image(systemName: tab.systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Palette.text)
                .frame(width: 52, height: 52)
                .background {
                    if isSelected {
                        Circle()
                            .fill(Palette.text)
                            .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                            .matchedGeometryEffect(id: "selectedTab", in: namespace)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
