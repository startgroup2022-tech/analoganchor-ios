import Foundation

/// Resolves the shared storage location used by the app and (later) its
/// extensions.
///
/// Phase 2 establishes the *architecture* only: the App Group container is the
/// single source of truth. Creating the App Group in the Apple Developer portal
/// is a manual step that must accompany this code — the helper degrades
/// gracefully to an app-local directory when the group is unavailable (e.g. in
/// unit tests or an unsigned simulator build) so the app never crashes on
/// launch.
public enum SharedStore {

    public enum StoreError: Error {
        case containerUnavailable
    }

    /// Returns the App Group container URL on Apple platforms, or nil elsewhere
    /// (e.g. Linux test runs).
    private static func appGroupContainer(fileManager: FileManager) -> URL? {
        #if canImport(Darwin)
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: AnalogAnchorConfig.appGroupIdentifier)
        #else
        return nil
        #endif
    }

    /// Directory that should contain the shared SwiftData store and any shared
    /// files. Prefers the App Group container; falls back to Application Support.
    ///
    /// The returned directory is created if missing, so callers (including
    /// extensions) can write immediately without a separate setup step.
    public static func directory(fileManager: FileManager = .default) -> URL {
        if let group = appGroupContainer(fileManager: fileManager) {
            return group
        }
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("AnalogAnchor", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    /// Whether the shared App Group container is actually available at runtime.
    /// Used to surface setup problems early instead of silently splitting data.
    public static func isAppGroupAvailable(fileManager: FileManager = .default) -> Bool {
        appGroupContainer(fileManager: fileManager) != nil
    }

    /// URL of the SwiftData store file inside the shared container.
    public static func databaseURL(fileManager: FileManager = .default) -> URL {
        directory(fileManager: fileManager).appendingPathComponent("AnalogAnchor.store")
    }

    /// URL of a shared JSON file, e.g. for lightweight cross-process hand-off.
    public static func sharedFile(named name: String, fileManager: FileManager = .default) -> URL {
        directory(fileManager: fileManager).appendingPathComponent(name)
    }
}
