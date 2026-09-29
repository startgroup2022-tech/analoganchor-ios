import Foundation

/// Partner / "Circle" accountability domain, ported from
/// `PartnerSessionPrefs`, `PartnerChallengeBroadcastReceiver` and
/// `AnchorViewModel.handlePartnerSessionPendingExpired` (Android).
///
/// Bluetooth transport is deliberately **not** ported here. This file models the
/// session lifecycle and its ledger/accountability effects; a future
/// `PartnerTransport` adapter (CoreBluetooth) would feed the same rules.
public enum PartnerDomain {

    /// `PartnerSessionPrefs.PENDING_GRACE_WINDOW_MS` — window for the partner to
    /// activate a pending session before it counts as broken.
    public static let pendingGraceWindow: TimeInterval = 5 * 60

    /// `PENDING` default session length in minutes.
    public static let defaultDurationMinutes = 60

    /// Penalty when a pending session is never activated
    /// (`Broke Circle Covenant: Shield Not Activated`).
    public static let brokeCovenantPenalty = 25

    /// Penalty when a started outing ends early (`Broken Sanctuary Outing Early`).
    public static let brokenOutingPenalty = 25

    /// Reward for a completed solo partner outing (default `points` extra).
    public static let partnerCompletionPoints = 40

    /// Reward for a completed group circle (`isGroup`).
    public static let groupCompletionPoints = 70

    /// Session lifecycle. `pending` is set when Analog Anchor launches a
    /// challenge; `active` is confirmed by the companion app's broadcast.
    public enum Status: String, Equatable, Sendable {
        case pending
        case active
        case completed
        case cancelled
    }

    public struct Session: Equatable, Sendable {
        public var id: String
        public var partnerName: String
        public var status: Status
        public var startedAt: Date
        public var durationMinutes: Int

        public init(
            id: String = UUID().uuidString,
            partnerName: String = "Partner",
            status: Status = .pending,
            startedAt: Date = Date(),
            durationMinutes: Int = PartnerDomain.defaultDurationMinutes
        ) {
            self.id = id
            self.partnerName = partnerName
            self.status = status
            self.startedAt = startedAt
            self.durationMinutes = durationMinutes
        }

        public var endDate: Date { startedAt.addingTimeInterval(Double(durationMinutes) * 60) }

        /// Ports `ActivePartnerSession.isExpired`: a pending session expires after
        /// the grace window; an active one expires at its scheduled end.
        public func isExpired(now: Date = Date()) -> Bool {
            switch status {
            case .pending:
                return now.timeIntervalSince(startedAt) > PartnerDomain.pendingGraceWindow
            case .active:
                return now >= endDate
            case .completed, .cancelled:
                return false
            }
        }

        /// Ports `remainingSeconds` / `remainingPendingSeconds`.
        public func remainingSeconds(now: Date = Date()) -> Int {
            switch status {
            case .pending:
                let remaining = startedAt.addingTimeInterval(PartnerDomain.pendingGraceWindow).timeIntervalSince(now)
                return max(0, Int(remaining))
            case .active:
                return max(0, Int(endDate.timeIntervalSince(now)))
            case .completed, .cancelled:
                return 0
            }
        }
    }

    /// Outcome the caller must apply to the ledger.
    public struct Settlement: Equatable, Sendable {
        public var points: Int
        public var reason: String
        public var status: String
        /// Whether this reward counts towards the weekly outdoor-partner quota
        /// (`outdoor_partner_count_this_week`).
        public var incrementsPartnerQuota: Bool
    }

    public enum PartnerError: Error, Equatable {
        case notCompletable
    }

    /// Ports the completion branch of `PartnerChallengeBroadcastReceiver`:
    /// success credits (40 solo / 70 group) and bumps the partner quota; failure
    /// applies a 25-point covenant penalty.
    public static func settleCompletion(
        isSuccess: Bool,
        isGroup: Bool,
        partnerName: String,
        durationMinutes: Int
    ) -> Settlement {
        if isSuccess {
            let points = isGroup ? groupCompletionPoints : partnerCompletionPoints
            let label = isGroup
                ? "Completed Group Sanctuary Circle with \(partnerName) (\(durationMinutes) min, +\(points) PTS)"
                : "Completed Partner Meshwar Al-Sakeenah with \(partnerName) (\(durationMinutes) min, +\(points) PTS)"
            return Settlement(
                points: points,
                reason: label,
                status: "outdoor_partner",
                incrementsPartnerQuota: true
            )
        }
        return Settlement(
            points: -brokenOutingPenalty,
            reason: "Broken Sanctuary Outing Early (-\(brokenOutingPenalty) PTS)",
            status: "penalty",
            incrementsPartnerQuota: false
        )
    }

    /// Ports `handlePartnerSessionPendingExpired`: a pending session that was
    /// never activated yields a -25 covenant penalty and a guilt banner.
    /// Returns `nil` when the session should be left alone.
    public static func settlementForExpiredPendingSession(
        _ session: Session,
        now: Date = Date()
    ) -> Settlement? {
        guard session.status == .pending, session.isExpired(now: now) else { return nil }
        return Settlement(
            points: -brokeCovenantPenalty,
            reason: "Broke Circle Covenant: Shield Not Activated",
            status: "penalty",
            incrementsPartnerQuota: false
        )
    }

    /// Ports `confirmActivation` from the companion broadcast: only a pending or
    /// missing session becomes active; a completed/cancelled one is ignored.
    public static func confirmActivation(
        _ session: inout Session,
        partnerName: String?,
        durationMinutes: Int,
        startTime: Date?,
        sessionId: String?
    ) {
        session.status = .active
        if let partnerName, !partnerName.isEmpty { session.partnerName = partnerName }
        session.durationMinutes = durationMinutes
        if let startTime { session.startedAt = startTime }
        if let sessionId, !sessionId.isEmpty { session.id = sessionId }
    }
}

/// BLE handshake seam. Implemented on iOS by `PartnerBluetoothTransport`
/// (CoreBluetooth, app target); the domain above depends only on this protocol.
public protocol PartnerTransport: Sendable {
    /// Whether the platform can advertise/scan for nearby partners.
    var isAvailable: Bool { get }
    /// Starts advertising this device as a partner host.
    func startAdvertising() async
    func stopAdvertising() async
    /// Streams discovered partners.
    func discoveredPartners() async -> [DiscoveredPartner]
}

/// A nearby partner found over the transport (`DiscoveredPartner` on Android).
public struct DiscoveredPartner: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var rssi: Int
    public var remainingMinutes: Int
    public var hasActiveSession: Bool

    public init(id: String, name: String, rssi: Int = 0, remainingMinutes: Int = 60, hasActiveSession: Bool = false) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.remainingMinutes = remainingMinutes
        self.hasActiveSession = hasActiveSession
    }
}

/// Transport stub that reports unavailability; used until CoreBluetooth lands so
/// the app never claims a pairing capability it does not have.
public struct UnavailablePartnerTransport: PartnerTransport {
    public init() {}
    public var isAvailable: Bool { false }
    public func startAdvertising() async {}
    public func stopAdvertising() async {}
    public func discoveredPartners() async -> [DiscoveredPartner] { [] }
}
