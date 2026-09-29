import Foundation
import AnalogAnchorKit

/// Nearby-mosque lookup over the public OpenStreetMap Overpass API.
///
/// Ports `queryNearbyMosques` from Android (same endpoint, same OSM query, same
/// 6 km radius, same "top 8 nearest" reduction). This is network code and
/// therefore lives in the **app target**, never in `AnalogAnchorKit/Domain` —
/// the Kit stays pure and Linux-testable.
///
/// No new backend is introduced: this is the identical third-party public API
/// the Android app already calls.
@MainActor
final class MosqueLookupService: ObservableObject {

    /// One candidate returned by Overpass (`NearbyMosqueCandidate` on Android).
    struct Candidate: Identifiable, Equatable, Sendable {
        public var id: String { "\(name.lowercased()):\(String(format: "%.5f:%.5f", latitude, longitude))" }
        public var name: String
        public var address: String
        public var latitude: Double
        public var longitude: Double
        public var distanceMeters: Int
    }

    enum LookupError: Error, LocalizedError {
        case badResponse(Int)
        case emptyBody
        case malformedJSON

        var errorDescription: String? {
            switch self {
            case .badResponse(let code): return "Mosque lookup failed (HTTP \(code))."
            case .emptyBody: return "Mosque lookup returned no data."
            case .malformedJSON: return "Mosque lookup returned an unexpected response."
            }
        }
    }

    /// `MOSQUE_LOOKUP_RADIUS_METERS` on Android.
    static let radiusMeters = 6_000

    @Published private(set) var candidates: [Candidate] = []
    @Published private(set) var isSearching = false
    @Published private(set) var lastError: String?
    @Published private(set) var status: String?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Runs the Overpass query around a coordinate. Never throws into the UI;
    /// failures set `lastError` so the view can show an honest message.
    func search(latitude: Double, longitude: Double) async {
        isSearching = true
        lastError = nil
        status = nil
        defer { isSearching = false }

        do {
            let raw = try await fetchElements(latitude: latitude, longitude: longitude)
            let reduced = Self.reduce(raw, origin: (latitude, longitude))
            candidates = reduced
            status = reduced.isEmpty
                ? "No OSM mosques found near this point."
                : "Found \(reduced.count) nearby mosques."
        } catch {
            candidates = []
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Networking

    private func fetchElements(latitude: Double, longitude: Double) async throws -> [Element] {
        let query = """
        [out:json][timeout:12];
        (
          node["amenity"="place_of_worship"]["religion"="muslim"](around:\(Self.radiusMeters),\(latitude),\(longitude));
          way["amenity"="place_of_worship"]["religion"="muslim"](around:\(Self.radiusMeters),\(latitude),\(longitude));
          relation["amenity"="place_of_worship"]["religion"="muslim"](around:\(Self.radiusMeters),\(latitude),\(longitude));
        );
        out center tags 24;
        """

        var components = URLComponents(string: "https://overpass-api.de/api/interpreter")!
        components.queryItems = [URLQueryItem(name: "data", value: query)]

        var request = URLRequest(url: components.url!)
        // Same descriptive User-Agent as Android (required by Overpass policy).
        request.setValue("AnalogAnchor/1.0 iOS mosque lookup", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LookupError.badResponse(http.statusCode)
        }
        guard !data.isEmpty else { throw LookupError.emptyBody }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = root["elements"] as? [[String: Any]] else {
            throw LookupError.malformedJSON
        }

        return elements.compactMap { element in
            let lat: Double
            let lng: Double
            if let directLat = element["lat"] as? Double, let directLng = element["lon"] as? Double {
                lat = directLat; lng = directLng
            } else if let center = element["center"] as? [String: Any],
                      let centerLat = center["lat"] as? Double,
                      let centerLng = center["lon"] as? Double {
                lat = centerLat; lng = centerLng
            } else {
                return nil
            }
            guard Self.isUsable(lat, lng) else { return nil }
            let tags = element["tags"] as? [String: Any] ?? [:]
            return Element(latitude: lat, longitude: lng, tags: tags)
        }
    }

    // MARK: - Reduction

    private struct Element {
        var latitude: Double
        var longitude: Double
        var tags: [String: Any]
    }

    /// Ports the Android reduction: friendly name fallback chain, address parts,
    /// de-duplication, distance sort and "top 8".
    static func reduce(_ elements: [Element], origin: (latitude: Double, longitude: Double)) -> [Candidate] {
        var seen = Set<String>()
        var result: [Candidate] = []

        for element in elements {
            let tags = element.tags
            let name = firstNonBlank([
                tags["name:ar"] as? String,
                tags["name:en"] as? String,
                tags["name"] as? String
            ]) ?? "Nearby Mosque"

            let address = firstNonBlank([
                (tags["addr:housenumber"] as? String),
                (tags["addr:street"] as? String),
                (tags["addr:suburb"] as? String),
                (tags["addr:city"] as? String),
                (tags["addr:emirate"] as? String),
                (tags["addr:country"] as? String)
            ]) ?? "Nearby sanctuary zone"

            let distance = Int(LocationService.distanceMeters(
                from: origin,
                to: (element.latitude, element.longitude)
            ).rounded())

            let key = "\(name.lowercased()):\(String(format: "%.5f:%.5f", element.latitude, element.longitude))"
            guard seen.insert(key).inserted else { continue }

            result.append(Candidate(
                name: name,
                address: address,
                latitude: element.latitude,
                longitude: element.longitude,
                distanceMeters: distance
            ))
        }

        return result.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(8).map { $0 }
    }

    private static func firstNonBlank(_ values: [String?]) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func isUsable(_ lat: Double, _ lng: Double) -> Bool {
        lat.isFinite && lng.isFinite && !(lat == 0 && lng == 0) && abs(lat) <= 90 && abs(lng) <= 180
    }
}
