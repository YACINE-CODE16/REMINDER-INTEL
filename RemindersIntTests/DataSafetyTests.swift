import Foundation
import SwiftData
import Testing
@testable import RemindersInt

/// Step 8a: data safety.
@MainActor
struct DataSafetyTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Deleting a session deletes its workout (cascade); recomputing then ignores its sets.
    @Test func prsAreRecomputedWithoutDeletedWorkout() throws {
        let context = try makeContext()
        let space = Space(name: "Salle", colorHex: "#34C759", sfSymbol: "dumbbell.fill")
        context.insert(space)
        let bench = Exercise(id: "bench_press", nameFR: "Développé couché", nameEN: "Bench press", aliases: [], muscleGroup: .chest, kind: .weightReps, isCustom: false)
        context.insert(bench)

        var sessions: [Session] = []
        for (index, weight) in [80.0, 85, 90].enumerated() {
            let start = Date(timeIntervalSince1970: 1_790_000_000 + Double(index) * 86_400)
            let session = Session(space: space, startedAt: start, endedAt: start.addingTimeInterval(3600))
            context.insert(session)
            let workout = Workout(session: session, template: nil)
            context.insert(workout)
            let entry = WorkoutEntry(order: 0, exercise: bench)
            entry.workout = workout
            context.insert(entry)
            let set = WorkoutSet(reps: 5, weightKg: weight, completedAt: start.addingTimeInterval(600))
            set.entry = entry
            context.insert(set)
            sessions.append(session)
        }
        try context.save()
        GymService.shared.recomputePRs(of: bench)
        #expect(bench.allSets.map(\.isPR) == [false, true, true])

        // The first workout goes: 85 becomes the first set ever, no longer a record.
        context.delete(sessions[0])
        try context.save()
        GymService.shared.recomputePRs(of: bench)
        #expect(bench.allSets.map(\.weightKg) == [85, 90])
        #expect(bench.allSets.map(\.isPR) == [false, true])
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 2)
    }

    // MARK: - Store loading

    private func temporaryStoreURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: StoreLoader.fileName)
    }

    /// A healthy store opens in place and keeps its data.
    @Test func healthyStoreOpens() throws {
        let url = try temporaryStoreURL()
        do {
            let first = StoreLoader.load(at: url)
            let context = try #require(first.container).mainContext
            context.insert(Space(name: "Perso", colorHex: "#FF375F", sfSymbol: "house.fill"))
            try context.save()
        }
        let second = StoreLoader.load(at: url)
        #expect(second.backupURL == nil)
        #expect(try #require(second.container).mainContext.fetchCount(FetchDescriptor<Space>()) == 1)
    }

    /// An unreadable file is kept as "default.store.broken-<date>" and an empty store replaces it.
    @Test func corruptedStoreIsKeptAsideAndReplaced() throws {
        let url = try temporaryStoreURL()
        try Data(repeating: 0x42, count: 4096).write(to: url)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let result = StoreLoader.load(at: url, now: now)
        let backup = try #require(result.backupURL)
        #expect(backup.lastPathComponent.hasPrefix("default.store.broken-"))
        #expect(FileManager.default.fileExists(atPath: backup.path()))
        #expect(try Data(contentsOf: backup) == Data(repeating: 0x42, count: 4096))
        let context = try #require(result.container).mainContext
        #expect(try context.fetchCount(FetchDescriptor<Space>()) == 0)
        context.insert(Space(name: "Perso", colorHex: "#FF375F", sfSymbol: "house.fill"))
        try context.save()
        #expect(FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func deletionMessageMentionsTheWorkout() throws {
        let context = try makeContext()
        let space = Space(name: "Salle", colorHex: "#34C759", sfSymbol: "dumbbell.fill")
        context.insert(space)
        let session = Session(space: space, startedAt: .now.addingTimeInterval(-3600), endedAt: .now)
        context.insert(session)
        #expect(TrackingView.deletionMessage(for: session).contains("session"))
        let workout = Workout(session: session, template: nil)
        context.insert(workout)
        let exercise = Exercise(id: "squat", nameFR: "Squat", nameEN: "Back squat", aliases: [], muscleGroup: .legs, kind: .weightReps, isCustom: false)
        context.insert(exercise)
        let entry = WorkoutEntry(order: 0, exercise: exercise)
        entry.workout = workout
        context.insert(entry)
        let set = WorkoutSet(reps: 5, weightKg: 100)
        set.entry = entry
        context.insert(set)
        try context.save()
        let message = TrackingView.deletionMessage(for: session)
        #expect(message.contains("séance de muscu"))
        #expect(message.contains("1 série"))
    }
}

/// Step 8a: location privacy.
struct LocationPrivacyTests {
    @Test func coordinatesAreRoundedToTwoDecimals() {
        #expect(PrayerLocator.rounded(48.85661) == 48.86)
        #expect(PrayerLocator.rounded(2.35222) == 2.35)
        #expect(PrayerLocator.rounded(-0.004) == 0)
    }

    /// Paris at full precision and rounded: prayer times within a minute.
    @Test func roundingKeepsPrayerTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!
        let exact = PrayerTimesCalculator(latitude: 48.85661, longitude: 2.35222).times(on: day, calendar: calendar)
        let rounded = PrayerTimesCalculator(latitude: 48.86, longitude: 2.35).times(on: day, calendar: calendar)
        for prayer in Prayer.allCases {
            #expect(abs(exact.time(of: prayer).timeIntervalSince(rounded.time(of: prayer))) <= 60)
        }
    }
}
