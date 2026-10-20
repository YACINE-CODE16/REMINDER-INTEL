import Foundation
import SwiftData

/// Every model of the current store. A new version adds SchemaV2 and a stage in AppMigrationPlan.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskItem.self, Space.self, Session.self, Goal.self, GoalStep.self,
            PrayerSettings.self, PrayerRecord.self,
            Exercise.self, WorkoutTemplate.self, TemplateItem.self, Workout.self, WorkoutEntry.self, WorkoutSet.self,
            Reminder.self,
        ]
    }
}

/// Empty for now: the first versioned schema. Later versions append their stages here.
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

/// Opens the store without ever crashing: explicit location (App Group, else Application
/// Support), and if the file cannot be opened, it is kept aside as "<name>.broken-<date>"
/// and an empty store is created.
enum StoreLoader {
    struct Result {
        /// nil only if even an in-memory store could not be created.
        var container: ModelContainer?
        /// Where the unreadable store was moved, when it happened.
        var backupURL: URL?
    }

    static let fileName = "default.store"

    /// The store SwiftData used implicitly so far: the App Group container once the app has
    /// the group entitlement (step 4), the app's own Application Support otherwise.
    static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
            ?? URL.applicationSupportDirectory
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appending(path: fileName)
    }

    static func load(at url: URL = defaultStoreURL(), fileManager: FileManager = .default, now: Date = .now) -> Result {
        if let container = try? open(at: url) {
            return Result(container: container, backupURL: nil)
        }
        let backup = moveAside(url, fileManager: fileManager, now: now)
        if let container = try? open(at: url) {
            return Result(container: container, backupURL: backup)
        }
        // Last resort: the app still runs, nothing is saved this time.
        let memory = try? ModelContainer(
            for: Schema(versionedSchema: SchemaV1.self),
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return Result(container: memory, backupURL: backup)
    }

    static func open(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, url: url)
        )
    }

    /// Renames the store and its -shm / -wal companions to "<name>.broken-<date>…".
    /// Returns the new location of the main file.
    @discardableResult
    static func moveAside(_ url: URL, fileManager: FileManager = .default, now: Date = .now) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let suffix = ".broken-\(formatter.string(from: now))"
        var moved: URL?
        for companion in ["", "-shm", "-wal"] {
            let source = URL(filePath: url.path() + companion)
            guard fileManager.fileExists(atPath: source.path()) else { continue }
            let destination = URL(filePath: url.path() + suffix + companion)
            do {
                try fileManager.moveItem(at: source, to: destination)
                if companion.isEmpty { moved = destination }
            } catch {
                // A file that cannot be moved is removed so a fresh store can be created.
                try? fileManager.removeItem(at: source)
            }
        }
        return moved
    }
}
