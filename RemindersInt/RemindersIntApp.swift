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
    private let container: ModelContainer

    init() {
        do {
            // Reminder stays in the schema only so V1 stores can be migrated.
            container = try ModelContainer(for: TaskItem.self, Space.self, Session.self, Goal.self, GoalStep.self, PrayerSettings.self, PrayerRecord.self, Exercise.self, WorkoutTemplate.self, TemplateItem.self, Workout.self, WorkoutEntry.self, WorkoutSet.self, Reminder.self)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        StoreSetup.run(in: container.mainContext)
        NotificationService.shared.configure(with: container)
        TrackingService.shared.configure(with: container)
        PrayerService.shared.configure(with: container)
        GymService.shared.configure(with: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, .app)
                .environment(\.calendar, .app)
                // The validated design is light-only; custom dark mode is out of V1 scope.
                .preferredColorScheme(.light)
        }
        .modelContainer(container)
    }
}
