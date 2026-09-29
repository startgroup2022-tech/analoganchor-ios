import Foundation

/// Authorization status for the Screen Time / Family Controls capability.
///
/// Maps 1:1 onto the states returned by `AuthorizationCenter`; the app target
/// performs the actual Apple call, the Kit only stores the portable value.
public enum ScreenTimeAuthorizationStatus: String, Codable, Sendable {
    case notDetermined
    case denied
    case approved
    /// The capability is not available at all (entitlement missing, unsupported OS).
    case unavailable
}

/// Errors surfaced by the Screen Time authorization flow. Real failures are
/// reported — never swallowed — so the UI can explain what happened.
public enum ScreenTimeAuthorizationError: Error, Equatable, LocalizedError {
    case entitlementMissing
    case frameworkUnavailable
    case systemError(String)

    public var errorDescription: String? {
        switch self {
        case .entitlementMissing:
            return "The Family Controls capability is not present in this build's provisioning profile."
        case .frameworkUnavailable:
            return "FamilyControls is not available on this platform."
        case .systemError(let message):
            return message
        }
    }
}

/// Result of an authorization attempt.
public struct ScreenTimeAuthorizationOutcome: Sendable {
    public let status: ScreenTimeAuthorizationStatus
    public let error: ScreenTimeAuthorizationError?

    public init(status: ScreenTimeAuthorizationStatus, error: ScreenTimeAuthorizationError? = nil) {
        self.status = status
        self.error = error
    }
}

/// Abstraction over the Screen Time authorization surface.
///
/// The concrete iOS implementation lives in the app target and is guarded by
/// `#if canImport(FamilyControls)`. The Kit only depends on this protocol, which
/// keeps domain logic free of Apple frameworks and Linux-testable.
public protocol ScreenTimeAuthorizing: AnyObject {
    /// Last known authorization status.
    var status: ScreenTimeAuthorizationStatus { get }

    /// Whether the Family Controls entitlement is present in this build.
    var isEntitlementAvailable: Bool { get }

    /// Requests authorization from the user and returns the real outcome.
    @discardableResult
    func requestAuthorization() async -> ScreenTimeAuthorizationOutcome

    /// Re-reads the current status from the system without prompting the user.
    /// Used on launch and when returning to the foreground, because a user can
    /// revoke Screen Time access in Settings at any time.
    @discardableResult
    func refreshAuthorizationStatus() async -> ScreenTimeAuthorizationStatus
}

/// Default no-op authorizer used in previews and tests.
public final class UnavailableScreenTimeAuthorizer: ScreenTimeAuthorizing {
    public var status: ScreenTimeAuthorizationStatus { .unavailable }
    public var isEntitlementAvailable: Bool { false }
    public init() {}
    @discardableResult
    public func requestAuthorization() async -> ScreenTimeAuthorizationOutcome {
        ScreenTimeAuthorizationOutcome(status: .unavailable, error: .frameworkUnavailable)
    }
    @discardableResult
    public func refreshAuthorizationStatus() async -> ScreenTimeAuthorizationStatus { .unavailable }
}
