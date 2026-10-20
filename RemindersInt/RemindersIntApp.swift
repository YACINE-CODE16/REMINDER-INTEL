//
//  RemindersIntApp.swift
//  RemindersInt
//
//  Created by Yacine Bask on 08/10/2026.
//

import SwiftUI
import SwiftData

@main
struct RemindersIntApp: App {
    /// nil only if not even an in-memory store could be created.
    private let container: ModelContainer?
    @State private var showsRecoveryAlert: Bool

    init() {
        // Never crashes: an unreadable store is kept aside and replaced by an empty one.
        let result = StoreLoader.load()
        container = result.container
        _showsRecoveryAlert = State(initialValue: result.backupURL != nil)
        guard let container else { return }
        StoreSetup.run(in: container.mainContext)
        NotificationService.shared.configure(with: container)
        TrackingService.shared.configure(with: container)
        PrayerService.shared.configure(with: container)
        GymService.shared.configure(with: container)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let container {
                    ContentView()
                        .modelContainer(container)
                } else {
                    ContentUnavailableView(
                        "Données indisponibles",
                        systemImage: "externaldrive.badge.exclamationmark",
                        description: Text("Les données n'ont pas pu être ouvertes. Redémarre l'app ; si le problème persiste, réinstalle-la depuis Xcode.")
                    )
                }
            }
            .environment(\.locale, .app)
            .environment(\.calendar, .app)
            // The validated design is light-only; custom dark mode is out of V1 scope.
            .preferredColorScheme(.light)
            .alert("Données non chargées", isPresented: $showsRecoveryAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Les données n'ont pas pu être chargées, une sauvegarde a été conservée.")
            }
        }
    }
}
