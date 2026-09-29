import Foundation
import AnalogAnchorKit

#if canImport(FamilyControls)
import FamilyControls
#endif

#if canImport(ManagedSettings)
import ManagedSettings
#endif

/// Encodes/decodes a `FamilyActivitySelection` for App-Group storage.
///
/// The Kit never interprets Apple token bytes; it round-trips the JSON produced
/// here. This type is the only place that knows how the opaque payload maps back
/// to `ApplicationToken` / `ActivityCategoryToken` / `WebDomainToken` sets.
enum ScreenTimeSelectionCodec {

    struct Decoded {
        #if canImport(FamilyControls)
        var applicationTokens: Set<ApplicationToken> = []
        var categoryTokens: Set<ActivityCategoryToken> = []
        var webDomainTokens: Set<WebDomainToken> = []
        #else
        var applicationTokens: Set<String> = []
        var categoryTokens: Set<String> = []
        var webDomainTokens: Set<String> = []
        #endif

        var isEmpty: Bool {
            applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
        }
    }

    /// Serializes a picker selection into the portable payload.
    #if canImport(FamilyControls)
    static func encode(_ selection: FamilyActivitySelection) -> ScreenTimeSelectionPayload {
        let encoder = JSONEncoder()
        let data = try? encoder.encode(selection)
        return ScreenTimeSelectionPayload(
            rawSelectionJSON: data,
            applicationCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count
        )
    }
    #endif

    /// Reconstructs Apple token sets from the payload. Returns an empty set if
    /// the payload is missing or was written by an incompatible build.
    static func decode(_ payload: ScreenTimeSelectionPayload) -> Decoded {
        #if canImport(FamilyControls)
        guard let data = payload.rawSelectionJSON,
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return Decoded()
        }
        return Decoded(
            applicationTokens: selection.applicationTokens,
            categoryTokens: selection.categoryTokens,
            webDomainTokens: selection.webDomainTokens
        )
        #else
        return Decoded()
        #endif
    }
}
