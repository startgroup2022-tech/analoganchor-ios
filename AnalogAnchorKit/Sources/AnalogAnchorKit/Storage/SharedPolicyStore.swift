import Foundation

/// App-Group-backed JSON store for the Screen Time policy + selection.
///
/// Extensions (DeviceActivity Monitor, Shield Configuration/Action) run in
/// separate processes and cannot read the main app's memory, so every value the
/// shields depend on is written here as plain JSON in the shared container.
///
/// This store never touches Apple frameworks, so it is fully unit-testable on
/// Linux (it falls back to an app-local directory when the App Group is absent).
public struct SharedPolicyStore {

    public enum Keys {
        public static let policy = AnalogAnchorConfig.SharedFileNames.policy
        public static let selection = AnalogAnchorConfig.SharedFileNames.selection
        public static let diagnostics = AnalogAnchorConfig.SharedFileNames.diagnostics
        public static let engineState = AnalogAnchorConfig.SharedFileNames.engineState
        public static let behaviorReport = AnalogAnchorConfig.SharedFileNames.behaviorReport
    }

    private let fileManager: FileManager

    /// Overrides the directory used for storage. Nil means "resolve via
    /// `SharedStore`" (the App Group container). Tests pass a temporary
    /// directory so they never share state.
    private let directoryOverride: URL?

    /// Last write error, surfaced to the UI / diagnostics instead of being
    /// silently dropped. Reading is intentionally non-throwing (missing files
    /// are normal), writing is not.
    public private(set) var lastError: Error?

    public init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directoryOverride = directory
    }

    private func url(for key: String) -> URL {
        if let directoryOverride {
            if !fileManager.fileExists(atPath: directoryOverride.path) {
                try? fileManager.createDirectory(at: directoryOverride, withIntermediateDirectories: true)
            }
            return directoryOverride.appendingPathComponent(key)
        }
        return SharedStore.sharedFile(named: key, fileManager: fileManager)
    }

    // MARK: - Policy

    public func loadPolicy() -> ScreenTimePolicy? {
        load(ScreenTimePolicy.self, key: Keys.policy)
    }

    /// Persists the policy. Returns `false` and records `lastError` on failure
    /// (e.g. the App Group container is unavailable and the fallback directory
    /// is not writable) rather than pretending the write succeeded.
    @discardableResult
    public mutating func savePolicy(_ policy: ScreenTimePolicy) -> Bool {
        save(policy, key: Keys.policy)
    }

    // MARK: - Selection

    public func loadSelection() -> ScreenTimeSelectionPayload {
        load(ScreenTimeSelectionPayload.self, key: Keys.selection) ?? .empty
    }

    @discardableResult
    public mutating func saveSelection(_ selection: ScreenTimeSelectionPayload) -> Bool {
        save(selection, key: Keys.selection)
    }

    // MARK: - Engine state (cross-process: who is current shield owner)

    public func loadEngineState() -> ScreenTimeEngineState? {
        load(ScreenTimeEngineState.self, key: Keys.engineState)
    }

    @discardableResult
    public mutating func saveEngineState(_ state: ScreenTimeEngineState) -> Bool {
        save(state, key: Keys.engineState)
    }

    // MARK: - Behavior report (written by the report extension)

    public func loadBehaviorReport() -> BehaviorReportSnapshot? {
        load(BehaviorReportSnapshot.self, key: Keys.behaviorReport)
    }

    @discardableResult
    public mutating func saveBehaviorReport(_ snapshot: BehaviorReportSnapshot) -> Bool {
        save(snapshot, key: Keys.behaviorReport)
    }

    // MARK: - Diagnostics (cross-process error surface)

    public func loadDiagnostics() -> [DiagnosticRecord] {
        load([DiagnosticRecord].self, key: Keys.diagnostics) ?? []
    }

    /// Appends a diagnostic record, keeping the newest entries. Extensions write
    /// here so failures are visible inside the app instead of silently vanishing.
    public mutating func appendDiagnostic(_ record: DiagnosticRecord, limit: Int = 50) {
        var records = loadDiagnostics()
        records.append(record)
        if records.count > limit {
            records = Array(records.suffix(limit))
        }
        save(records, key: Keys.diagnostics)
    }

    public mutating func clearDiagnostics() {
        do {
            try fileManager.removeItem(at: url(for: Keys.diagnostics))
        } catch {
            lastError = error
        }
    }

    // MARK: - Generic coding

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    @discardableResult
    private mutating func save<T: Encodable>(_ value: T, key: String) -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(value)
            try data.write(to: url(for: key), options: .atomic)
            lastError = nil
            return true
        } catch {
            lastError = error
            return false
        }
    }
}

/// A single cross-process diagnostic entry.
public struct DiagnosticRecord: Codable, Equatable, Sendable, Identifiable {

    public enum Severity: String, Codable, Sendable { case info, warning, error }

    public var id: UUID
    public var date: Date
    public var severity: Severity
    /// Which process recorded it (app, monitor, shield, …).
    public var source: String
    public var message: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        severity: Severity,
        source: String,
        message: String
    ) {
        self.id = id
        self.date = date
        self.severity = severity
        self.source = source
        self.message = message
    }
}
