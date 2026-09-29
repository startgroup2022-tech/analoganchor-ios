import Foundation

/// App-Group-backed store for raised behaviour-rule flags.
///
/// Mirrors Android's `RuleFlag` table but keeps the app target free of
/// persistence logic and stays fully unit-testable on Linux (it degrades to an
/// app-local directory when the App Group is absent, exactly like
/// `SharedPolicyStore`).
public actor BehaviorFlagStore: BehaviorRuleRepository {

    private let fileManager: FileManager
    private let directoryOverride: URL?

    /// Keeps the newest N flags so the file cannot grow without bound.
    private let limit: Int

    public init(fileManager: FileManager = .default, directory: URL? = nil, limit: Int = 200) {
        self.fileManager = fileManager
        self.directoryOverride = directory
        self.limit = limit
    }

    private func url() -> URL {
        if let directoryOverride {
            if !fileManager.fileExists(atPath: directoryOverride.path) {
                try? fileManager.createDirectory(at: directoryOverride, withIntermediateDirectories: true)
            }
            return directoryOverride.appendingPathComponent("behavior-flags.json")
        }
        return SharedStore.sharedFile(named: "behavior-flags.json", fileManager: fileManager)
    }

    public func save(_ flags: [BehaviorRules.Flag]) async {
        var existing = await load()
        existing.append(contentsOf: flags)
        if existing.count > limit {
            existing = Array(existing.suffix(limit))
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(existing) {
            try? data.write(to: url(), options: .atomic)
        }
    }

    public func load() async -> [BehaviorRules.Flag] {
        guard let data = try? Data(contentsOf: url()) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([BehaviorRules.Flag].self, from: data)) ?? []
    }

    public func count(of type: BehaviorRules.FlagType, since date: Date) async -> Int {
        await load().filter { $0.flagType == type && $0.createdAt >= date }.count
    }
}
