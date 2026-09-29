import Foundation

/// Encodes / decodes Analog Anchor emergency access tokens.
///
/// Direct port of the token logic in `AnchorViewModel.kt` (Android):
/// `normalizeMaskedToken`, `parseAccessTokenFromToken`, `parseSerialPayload`,
/// `serialChecksum`, `decodeTokenPin` and `tokenEncodeAlphabet`.
///
/// ## Token formats
/// - Serial:   `AA-ANCHOR-<coverA>-<payload>-<coverB>-<coverC>-<coverD>-<checksum>-EXP60`
/// - Legacy:   `AA-<ENCODED_PIN>-EXP60`
/// - Decoy:    the same shell with a `-DEC60` suffix (illusory unlock).
///
/// ## PIN unification (important)
/// The Android source contained several hard-coded numeric literals across the
/// code base that could be confused with the emergency PIN decoder:
/// `5222`, `8888`, `arrazi`, `2555`, `3555` and the decoy `4829`.
/// Verified against the code:
///   - `5222` / `8888` / `arrazi` are the *local in-app App PIN* accepted by
///     `ProtectedAppsBottomSheet.kt`. They belong to the app-lock feature, not
///     to token decoding, and are NOT secrets transmitted anywhere.
///   - `2555` / `3555` appear only in the iOS *specification document*, not in
///     the shipped Android code, and do not match the token decoder.
///   - `4829` is the decoy PIN returned for `-DEC60` tokens.
/// This port centralizes the decoy value and never hard-codes a real PIN: the
/// real PIN is always derived from the token payload.
public enum TokenCodec {

    /// Decoy PIN returned for illusory `-DEC60` tokens (mirrors Android).
    public static let decoyPin = "4829"

    private static let serialAlphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"

    public struct ParsedAccessToken: Equatable {
        public let encodedPin: String
        public let requestNumber: Int
    }

    public enum TokenKind: Equatable {
        case expiring(minutes: Int)
        case decoy
    }

    // MARK: - Alphabet per request number

    /// Substitution alphabet used to decode the encoded PIN segment.
    /// Code 1 map: 0->Q, 1->W, 2->E, 3->R, 4->T, 5->A, 6->S, 7->D, 8->F, 9->G
    /// Code 2 map: 0->Z, 1->Y, 2->X, 3->C, 4->V, 5->B, 6->N, 7->M, 8->H, 9->J
    /// Code 3 map: 0->P, 1->U, 2->L, 3->K, 4->A, 5->G, 6->F, 7->D, 8->S, 9->E
    public static func encodeAlphabet(forRequestNumber requestNumber: Int) -> String? {
        switch requestNumber {
        case 1: return "QWERTASDFG"
        case 2: return "ZYXCVBNMHJ"
        case 3: return "PULKAGFDSE"
        default: return nil
        }
    }

    // MARK: - Kind

    public static func kind(of token: String) -> TokenKind? {
        let normalized = normalize(token)
        if normalized.hasSuffix("-DEC60") || normalized.hasSuffix("DEC60") {
            return .decoy
        }
        if normalized.hasSuffix("-EXP60") || normalized.hasSuffix("EXP60") {
            return .expiring(minutes: 60)
        }
        return nil
    }

    public static func isDecoy(_ token: String) -> Bool {
        kind(of: token) == .decoy
    }

    // MARK: - Normalization

    /// Normalizes a raw, possibly Arabic-digit / bidi-contaminated token input.
    public static func normalize(_ token: String) -> String {
        var compact = normalizeAsciiDigits(token.precomposedStringWithCompatibilityMapping)
            .uppercased(with: Locale(identifier: "en_US_POSIX"))

        let dashVariants: [Character] = ["\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}", "\u{FE63}", "\u{FF0D}"]
        compact = String(compact.map { dashVariants.contains($0) ? "-" : $0 })

        // Strip whitespace and bidi control characters.
        let stripped = compact.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x20, 0xA0, 0x61C, 0x200B, 0x200C, 0x200D, 0x200E, 0x200F,
                 0x202A...0x202E, 0x2066...0x2069, 0xFEFF:
                return false
            default:
                return CharacterSet.whitespaces.contains(scalar) == false
            }
        }
        compact = String(String.UnicodeScalarView(stripped))

        if let groups = serialGroups(in: compact) {
            return buildSerialToken(groups: groups)
        }
        if let encoded = legacyEncodedPin(in: compact) {
            return "AA-\(encoded)-EXP60"
        }
        return compact
    }

    // MARK: - Parsing

    /// Parses a normalized token into its encoded PIN + request number.
    public static func parse(_ token: String) -> ParsedAccessToken? {
        let clean = normalize(token)

        if let encoded = legacyEncodedPin(in: clean) {
            return ParsedAccessToken(encodedPin: encoded, requestNumber: 1)
        }
        guard let groups = serialGroups(in: clean) else { return nil }

        let coverA = groups[0], payload = groups[1]
        let coverB = groups[2], coverC = groups[3], coverD = groups[4], checksum = groups[5]
        let expected = serialChecksum(coverA + payload + coverB + coverC + coverD)
        guard checksum == expected else { return nil }

        return parseSerialPayload(payload)
    }

    /// Returns the decoded numeric PIN, or the decoy PIN for `-DEC60` tokens.
    public static func decodedPin(from token: String) -> String? {
        let clean = normalize(token)
        if clean.hasSuffix("-DEC60") || clean.hasSuffix("DEC60") {
            return decoyPin
        }
        guard let parsed = parse(clean) else { return nil }
        return decodePin(encoded: parsed.encodedPin, requestNumber: parsed.requestNumber)
    }

    public static func isAccessTokenShape(_ token: String) -> Bool {
        let normalized = normalize(token)
        if normalized.hasSuffix("-DEC60") || normalized.hasSuffix("DEC60") {
            if let groups = decoySerialGroups(in: normalized) {
                return groups.count == 6
            }
        }
        return parse(normalized) != nil
    }

    // MARK: - PIN decoding

    public static func decodePin(encoded: String, requestNumber: Int = 1) -> String? {
        guard let alphabet = encodeAlphabet(forRequestNumber: requestNumber) else { return nil }
        let chars = Array(alphabet)
        var digits = ""
        for ch in encoded {
            guard let idx = chars.firstIndex(of: ch) else { return nil }
            digits.append(Character(String(idx)))
        }
        return digits
    }

    // MARK: - Serial helpers

    private static func parseSerialPayload(_ payload: String) -> ParsedAccessToken? {
        guard let first = payload.first else { return nil }
        let requestNumber: Int
        switch first {
        case "U": requestNumber = 2
        case "V": requestNumber = 3
        default: requestNumber = 1
        }
        let lengthIndex = (requestNumber == 1) ? 0 : 1
        let payloadChars = Array(payload)
        guard lengthIndex < payloadChars.count else { return nil }
        let pinLength: Int
        switch payloadChars[lengthIndex] {
        case "K": pinLength = 4
        case "L": pinLength = 5
        case "M": pinLength = 6
        case "N": pinLength = 7
        case "P": pinLength = 8
        default: return nil
        }
        let start = lengthIndex + 1
        guard start + pinLength <= payloadChars.count else { return nil }
        let encodedPin = String(payloadChars[start..<(start + pinLength)])
        guard let alphabet = encodeAlphabet(forRequestNumber: requestNumber),
              encodedPin.count == pinLength,
              encodedPin.allSatisfy({ alphabet.contains($0) }) else {
            return nil
        }
        return ParsedAccessToken(encodedPin: encodedPin, requestNumber: requestNumber)
    }

    public static func serialChecksum(_ value: String) -> String {
        var out = ""
        let alphabetChars = Array(serialAlphabet)
        for round in 0..<5 {
            var acc: Int64 = 17 + Int64(round) * 101
            for (index, char) in value.enumerated() {
                acc = (acc * 33 + Int64(char.unicodeScalars.first?.value ?? 0) + Int64(index * (round + 7))) % 1_000_000_007
            }
            let idx = Int(acc % Int64(alphabetChars.count))
            out.append(alphabetChars[idx])
        }
        return out
    }

    private static func buildSerialToken(groups: [String]) -> String {
        "AA-ANCHOR-\(groups[0])-\(groups[1])-\(groups[2])-\(groups[3])-\(groups[4])-\(groups[5])-EXP60"
    }

    // MARK: - Regex extraction (mirrors Android patterns)

    private static func legacyEncodedPin(in text: String) -> String? {
        match(text, pattern: "AA-?([QWERTASDFG]{4,8})-?EXP60", group: 1)
    }

    /// Returns [coverA, payload, coverB, coverC, coverD, checksum] for EXP60 tokens.
    private static func serialGroups(in text: String) -> [String]? {
        let pattern = "AA-?ANCHOR-?([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5})-?((?:[KLMNP][23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8})|(?:[UV][KLMNP][23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}))-?([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5})-?([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5})-?([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5})-?([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5})-?EXP60"
        return groups(text, pattern: pattern)
    }

    private static func decoySerialGroups(in text: String) -> [String]? {
        let pattern = "AA-?ANCHOR-?([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5})-?((?:[KLMNP][23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8})|(?:[UV][KLMNP][23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{8}))-?([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5})-?([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5})-?([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5})-?([23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{5})-?DEC60"
        return groups(text, pattern: pattern)
    }

    private static func match(_ text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, options: [], range: range),
              result.numberOfRanges > group,
              let r = Range(result.range(at: group), in: text) else {
            return nil
        }
        return String(text[r])
    }

    private static func groups(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = regex.firstMatch(in: text, options: [], range: range) else { return nil }
        var out = [String]()
        for i in 1..<result.numberOfRanges {
            guard let r = Range(result.range(at: i), in: text) else { return nil }
            out.append(String(text[r]))
        }
        return out.count == 6 ? out : nil
    }

    private static func normalizeAsciiDigits(_ value: String) -> String {
        var out = ""
        for char in value {
            if let n = char.wholeNumberValue, (0...9).contains(n) {
                out.append(Character(String(n)))
            } else {
                out.append(char)
            }
        }
        return out
    }
}
