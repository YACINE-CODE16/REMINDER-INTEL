import SwiftUI

struct SettingsView: View {
    @AppStorage(AppStorageKey.defaultRepeatInterval) private var defaultRepeatInterval: RepeatInterval = .every15min

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
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
    }
}

#Preview {
    SettingsView()
        .background(AppBackground())
}
