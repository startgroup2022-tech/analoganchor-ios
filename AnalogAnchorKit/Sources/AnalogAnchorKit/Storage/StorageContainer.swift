import Foundation

#if canImport(SwiftData)
import SwiftData

/// Owns the shared SwiftData container for Analog Anchor.
///
/// The container always points at `SharedStore.databaseURL`, so the app and
/// (from Phase 3) its extensions observe the same store. When the App Group is
/// unavailable the container still works locally, which keeps simulator builds
/// and previews functional without an Apple Developer configuration.
public enum StorageContainer {

    /// Builds the shared model container.
    public static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            ProtectedApp.self,
            ScheduleWindow.self,
            LedgerEntry.self,
            SessionRecord.self,
            UnlockRequestRecord.self
        ])

        let configuration: ModelConfiguration
        if inMemory || !SharedStore.isAppGroupAvailable() {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        } else {
            configuration = ModelConfiguration(schema: schema, url: SharedStore.databaseURL())
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
#endif
