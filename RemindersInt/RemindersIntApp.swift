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
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, .app)
                .environment(\.calendar, .app)
                // The validated design is light-only; custom dark mode is out of V1 scope.
                .preferredColorScheme(.light)
        }
        .modelContainer(for: Reminder.self)
    }
}
