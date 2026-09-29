import Foundation

/// Platform-service seams.
///
/// Each protocol describes what the *domain* needs from a device capability, so
/// iOS adapters can implement it against Apple frameworks while the domain stays
/// free of `CoreLocation`, `CoreMotion`, `CoreNFC`, `UIKit` and
/// `UserNotifications`. These are deliberately small — only the operations the
/// app actually performs today — and are implemented by the existing services in
/// the app target.

/// One-shot location access for prayer-time calculation and sanctuary checks.
@MainActor
public protocol LocationProviding: AnyObject {
    /// Whether the user has granted at least when-in-use access.
    var isAuthorized: Bool { get }
    /// Requests the minimal permission; safe to call repeatedly.
    func requestAuthorization()
    /// Current coordinate, or `nil` when unavailable.
    func currentCoordinate() async -> (latitude: Double, longitude: Double)?
}

/// Motion capabilities the domain consumes: step counts and the face-down
/// invariant for the focus ritual.
@MainActor
public protocol MotionProviding: AnyObject {
    var isStepCountingAvailable: Bool { get }
    /// Steps counted between two instants.
    func steps(from start: Date, to end: Date) async -> Int
}

/// NFC tag reading for the physical Anchor / Fajr architecture.
@MainActor
public protocol NFCProviding: AnyObject {
    var isSupported: Bool { get }
    /// Last scanned tag identifier, if any.
    var lastTagID: String? { get }
}

/// Proof-photo capture for the whiteboard flow.
@MainActor
public protocol CameraProviding: AnyObject {
    var isCameraAvailable: Bool { get }
    /// Path of the most recently captured image, if any.
    var lastCapturedImagePath: String? { get }
}

/// Local notification scheduling (prayer reminders, Soft Landing, alarms).
@MainActor
public protocol NotificationProviding: AnyObject {
    /// Schedules a local notification.
    func schedule(id: String, title: String, body: String, at date: Date) async
    /// Cancels a previously scheduled notification.
    func cancel(id: String)
}
