import Foundation

/// Parses a user-supplied location query into coordinates.
///
/// Port of `com.analoganchor.app.util.LocationCodeParser` (Android). Supports:
///   - raw "lat, lng" coordinates
///   - Google Plus Codes (full or short, recovered against a reference point)
public enum LocationCodeParser {

    /// Default Bahrain reference for recovering short Plus Codes (e.g. 6H7J+2XR).
    public static let bahrainDefaultLat = 26.2285
    public static let bahrainDefaultLng = 50.5860

    public struct ParsedLocation: Equatable {
        public let latitude: Double
        public let longitude: Double
        public let title: String
        public let address: String
    }

    public static func parse(
        _ query: String,
        referenceLatitude: Double = bahrainDefaultLat,
        referenceLongitude: Double = bahrainDefaultLng
    ) -> ParsedLocation? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // 1. Direct lat/lng coordinate match.
        if let coord = parseCoordinates(trimmed) {
            return ParsedLocation(
                latitude: coord.0,
                longitude: coord.1,
                title: String(format: "GPS: %.5f, %.5f", coord.0, coord.1),
                address: trimmed
            )
        }

        // 2. Plus Code match.
        if let code = firstPlusCode(in: trimmed) {
            if let olc = try? OpenLocationCode(code) {
                let resolved: OpenLocationCode
                if olc.isShort {
                    let refLat = (referenceLatitude != 0.0 && referenceLatitude != -999.0) ? referenceLatitude : bahrainDefaultLat
                    let refLng = (referenceLongitude != 0.0 && referenceLongitude != -999.0) ? referenceLongitude : bahrainDefaultLng
                    guard let recovered = try? olc.recover(referenceLatitude: refLat, referenceLongitude: refLng) else {
                        return nil
                    }
                    resolved = recovered
                } else {
                    resolved = olc
                }
                guard let area = try? resolved.decode() else { return nil }
                return ParsedLocation(
                    latitude: area.centerLatitude,
                    longitude: area.centerLongitude,
                    title: "Google Plus Code: \(code)",
                    address: trimmed
                )
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static func parseCoordinates(_ text: String) -> (Double, Double)? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" })
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lng = Double(parts[1]),
              lat >= -90.0, lat <= 90.0,
              lng >= -180.0, lng <= 180.0 else {
            return nil
        }
        return (lat, lng)
    }

    private static func firstPlusCode(in text: String) -> String? {
        // Regex mirrors the Android PLUS_CODE_PATTERN.
        let pattern = "\\b([23456789CFGHJMPQRVWX]{4,8}\\+[23456789CFGHJMPQRVWX]{2,4})\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let codeRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[codeRange]).uppercased()
    }
}
