import Foundation

#if canImport(SwiftData)
import SwiftData

/// SwiftData entities for Analog Anchor (iOS).
///
/// These mirror the Android Room entities
/// (`ShieldEntity`, `ScheduleEntity`, `SessionLog`, `ProofMission`,
/// `UnlockSession`, `RecoveryRecord`, `RuleFlag`) but are intentionally
/// future-proofed for the Screen Time layer: instead of storing raw Android
/// package names, protected apps are referenced by an opaque
/// `familyActivityTokenData` blob that Phase 3 will populate with
/// `ApplicationToken` data. This keeps the Android `packageName` concept out of
/// the iOS schema.
@Model
public final class ProtectedApp {
    @Attribute(.unique) public var id: UUID
    public var displayName: String
    public var createdAt: Date

    /// Opaque identifier once Screen Time tokens exist (Phase 3). Nil in Phase 2.
    public var familyActivityTokenData: Data?

    /// Strict daily ceiling in minutes (never nil-bypassable; defaults to 60).
    public var dailyLimitMinutes: Int

    /// Whether the app is inside an active shield schedule.
    public var isShielded: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        createdAt: Date = Date(),
        familyActivityTokenData: Data? = nil,
        dailyLimitMinutes: Int = AnalogAnchorConfig.defaultProtectedAppDailyLimitMinutes,
        isShielded: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.familyActivityTokenData = familyActivityTokenData
        self.dailyLimitMinutes = dailyLimitMinutes
        self.isShielded = isShielded
    }
}

/// A named time window (bedtime, wind-down, study block).
@Model
public final class ScheduleWindow {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var startMinutes: Int       // minutes from midnight
    public var endMinutes: Int         // minutes from midnight (may cross midnight)
    public var isActive: Bool
    public var interceptNotifications: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        startMinutes: Int,
        endMinutes: Int,
        isActive: Bool = true,
        interceptNotifications: Bool = false
    ) {
        self.id = id
        self.name = name
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.isActive = isActive
        self.interceptNotifications = interceptNotifications
    }
}

/// A single ledger transaction (Reserve Ledger).
@Model
public final class LedgerEntry {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var points: Int
    public var reason: String
    public var category: String
    public var isPenalty: Bool
    public var status: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        points: Int,
        reason: String,
        category: String,
        isPenalty: Bool,
        status: String = "logged"
    ) {
        self.id = id
        self.date = date
        self.points = points
        self.reason = reason
        self.category = category
        self.isPenalty = isPenalty
        self.status = status
    }
}

/// A completed focus / ritual session.
@Model
public final class SessionRecord {
    @Attribute(.unique) public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var durationMinutes: Int
    public var nfcTagID: String?
    public var pickupCount: Int
    public var verificationStatus: String
    public var reflectionNote: String?
    public var proofImagePath: String?

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date? = nil,
        durationMinutes: Int,
        nfcTagID: String? = nil,
        pickupCount: Int = 0,
        verificationStatus: String = "pending",
        reflectionNote: String? = nil,
        proofImagePath: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMinutes = durationMinutes
        self.nfcTagID = nfcTagID
        self.pickupCount = pickupCount
        self.verificationStatus = verificationStatus
        self.reflectionNote = reflectionNote
        self.proofImagePath = proofImagePath
    }
}

/// An emergency unlock request / cooling-window record.
@Model
public final class UnlockRequestRecord {
    @Attribute(.unique) public var id: UUID
    public var requestedAt: Date
    public var cooldownEndsAt: Date
    public var expiresAt: Date
    public var state: String          // REQUESTED / COOLING / ACTIVE / EXPIRED
    public var reason: String?
    public var isDecoy: Bool

    public init(
        id: UUID = UUID(),
        requestedAt: Date = Date(),
        cooldownEndsAt: Date,
        expiresAt: Date,
        state: String = "REQUESTED",
        reason: String? = nil,
        isDecoy: Bool = false
    ) {
        self.id = id
        self.requestedAt = requestedAt
        self.cooldownEndsAt = cooldownEndsAt
        self.expiresAt = expiresAt
        self.state = state
        self.reason = reason
        self.isDecoy = isDecoy
    }
}
#endif
