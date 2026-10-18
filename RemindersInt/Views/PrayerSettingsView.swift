import SwiftUI
import SwiftData

/// Prayer module settings: place, calculation, adjustments, notifications.
struct PrayerSettingsView: View {
    @Bindable var settings: PrayerSettings
    /// Shown when the module was just switched on and the location was refused.
    var locationRefused = false

    @Environment(\.dismiss) private var dismiss
    @State private var isLocating = false
    @State private var locationFailed = false
    @State private var query = ""
    @State private var results: [PrayerLocator.Place] = []
    @State private var isConfirmingDeactivation = false

    private static let rowBackground = Color.white.opacity(0.7)

    var body: some View {
        NavigationStack {
            Form {
                placeSection
                calculationSection
                adjustmentsSection
                notificationsSection
                Section {
                    Button("Désactiver le module", role: .destructive) { isConfirmingDeactivation = true }
                } footer: {
                    Text("Les prières déjà cochées sont conservées.")
                }
                .listRowBackground(Self.rowBackground)
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle("Réglages Prière")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", role: .confirm) { dismiss() }
                }
            }
            .confirmationDialog("Désactiver le module Prière ?", isPresented: $isConfirmingDeactivation, titleVisibility: .visible) {
                Button("Désactiver", role: .destructive) {
                    if let space = settings.space { PrayerService.shared.deactivate(space) }
                    dismiss()
                }
                Button("Garder", role: .cancel) {}
            } message: {
                Text("L'écran Prière et ses notifications disparaissent de l'espace. L'historique reste enregistré.")
            }
            .task(id: query) {
                // Debounced city search.
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                results = await PrayerLocator.search(query)
            }
            .onDisappear {
                try? settings.modelContext?.save()
                PrayerService.shared.refresh()
            }
        }
    }

    // MARK: - Place

    private var placeSection: some View {
        Section {
            HStack {
                Label(settings.cityName, systemImage: settings.hasLocation ? "location.fill" : "location.slash")
                    .foregroundStyle(Palette.text)
                Spacer()
                if isLocating { ProgressView() }
            }
            Button("Actualiser la position", systemImage: "location") {
                Task { await locate() }
            }
            .disabled(isLocating)
            TextField("Rechercher une ville", text: $query)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            ForEach(results) { place in
                Button {
                    PrayerLocator.apply(place, to: settings)
                    query = ""
                    results = []
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).foregroundStyle(Palette.text)
                        if let detail = place.detail {
                            Text(detail).font(.caption).foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Lieu")
        } footer: {
            if locationRefused || locationFailed {
                Text("Localisation indisponible ou refusée : cherche ta ville ci-dessus.")
            } else if !settings.hasLocation {
                Text("Paris est utilisé tant qu'aucune position n'est choisie.")
            }
        }
        .listRowBackground(Self.rowBackground)
    }

    private func locate() async {
        isLocating = true
        locationFailed = false
        if let place = await PrayerLocator.currentPlace() {
            PrayerLocator.apply(place, to: settings)
        } else {
            locationFailed = true
        }
        isLocating = false
    }

    // MARK: - Calculation

    private var calculationSection: some View {
        Section("Calcul") {
            Picker("Méthode", selection: $settings.method) {
                ForEach(PrayerMethod.allCases) { method in
                    Text(method.label).tag(method)
                }
            }
            Picker("Asr", selection: $settings.asrMadhab) {
                ForEach(AsrMadhab.allCases) { madhab in
                    Text(madhab.label).tag(madhab)
                }
            }
        }
        .listRowBackground(Self.rowBackground)
    }

    private func adjustment(_ prayer: Prayer) -> Binding<Int> {
        Binding(
            get: { settings.adjustments[prayer] ?? 0 },
            set: { value in
                var adjustments = settings.adjustments
                adjustments[prayer] = value
                settings.adjustments = adjustments
            }
        )
    }

    private var adjustmentsSection: some View {
        Section {
            ForEach(Prayer.allCases) { prayer in
                Stepper(value: adjustment(prayer), in: -30...30) {
                    HStack {
                        Text(prayer.name)
                        Spacer()
                        Text(Self.minutes(settings.adjustments[prayer] ?? 0))
                            .monospacedDigit()
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
            Button("Préréglage Grande Mosquée de Paris") {
                settings.method = .franceMuslims12
                settings.adjustments = PrayerTimesCalculator.grandeMosqueeDeParisAdjustments
            }
            Button("Remettre à zéro") {
                settings.adjustments = [:]
            }
        } header: {
            Text("Ajustements")
        } footer: {
            Text("Le préréglage ajoute au calcul 12° les minutes de précaution du calendrier de la Grande Mosquée de Paris : Fajr −5, Dhuhr +5, Maghrib +2, Isha +4.")
        }
        .listRowBackground(Self.rowBackground)
    }

    /// "0 min", "+5 min", "−5 min".
    static func minutes(_ value: Int) -> String {
        value == 0 ? "0 min" : (value > 0 ? "+\(value) min" : "−\(-value) min")
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle("À l'heure de l'adhan", isOn: $settings.notifyAtAdhan)
            Toggle("Relancer jusqu'à la coche", isOn: $settings.repeatUntilDone)
            if settings.repeatUntilDone {
                Picker("Intervalle", selection: $settings.repeatInterval) {
                    ForEach(RepeatInterval.allCases.filter { $0 != .none }) { interval in
                        Text(interval.label).tag(interval)
                    }
                }
            }
            Toggle("Mode discret (sans son)", isOn: $settings.quietMode)
        } header: {
            Text("Notifications")
        } footer: {
            Text("Les relances s'arrêtent à la prière suivante ou dès que la prière est cochée.")
        }
        .tint(Palette.green)
        .listRowBackground(Self.rowBackground)
    }
}
