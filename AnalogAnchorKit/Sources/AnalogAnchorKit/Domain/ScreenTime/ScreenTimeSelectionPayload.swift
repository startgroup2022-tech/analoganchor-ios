import Foundation

/// Portable, Codable snapshot of the user's FamilyActivityPicker selection.
///
/// The real `FamilyActivitySelection` contains opaque Apple tokens
/// (`ApplicationToken`, `ActivityCategoryToken`, `WebDomainToken`). The app
/// encodes that selection to JSON and stores it here; this struct is the
/// App-Group-safe representation the extensions and the policy layer read.
///
/// `rawSelectionJSON` is deliberately opaque to this layer — the Kit never
/// interprets Apple token bytes, it only round-trips them. `applicationCount`
/// and `categoryCount` are denormalised for UI display without decoding.
public struct ScreenTimeSelectionPayload: Codable, Equatable, Sendable {

    /// JSON-encoded `FamilyActivitySelection` produced by the app target.
    /// Nil when the user has not chosen anything yet.
    public var rawSelectionJSON: Data?

    /// Denormalised counts for display / diagnostics.
    public var applicationCount: Int
    public var categoryCount: Int
    public var webDomainCount: Int

    public var isEmpty: Bool { applicationCount == 0 && categoryCount == 0 && webDomainCount == 0 }

    public init(
        rawSelectionJSON: Data? = nil,
        applicationCount: Int = 0,
        categoryCount: Int = 0,
        webDomainCount: Int = 0
    ) {
        self.rawSelectionJSON = rawSelectionJSON
        self.applicationCount = applicationCount
        self.categoryCount = categoryCount
        self.webDomainCount = webDomainCount
    }

    public static let empty = ScreenTimeSelectionPayload()
}
