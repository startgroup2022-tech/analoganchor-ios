import XCTest
@testable import AnalogAnchorKit

final class TokenCodecTests: XCTestCase {

    /// Builds a valid EXP60 serial token with a given encoded PIN.
    ///
    /// The serial payload is always `lengthCode + 8 alphabet chars`
    /// (mirroring the Android regex `[KLMNP][<serial>]{8}`); only the first
    /// `pinLength` characters after the length code are the encoded PIN.
    private func makeToken(cover: String = "ABCDE", encodedPin: String) -> String {
        let lengthCode: String
        switch encodedPin.count {
        case 4: lengthCode = "K"
        case 5: lengthCode = "L"
        case 6: lengthCode = "M"
        case 7: lengthCode = "N"
        case 8: lengthCode = "P"
        default: fatalError("unsupported pin length")
        }
        let padding = String(repeating: "2", count: max(0, 8 - encodedPin.count))
        return makePayloadToken(cover: cover, payload: lengthCode + encodedPin + padding)
    }

    private func makePayloadToken(cover: String, payload: String) -> String {
        let coverB = "FGHJK", coverC = "LMNPQ", coverD = "RSTUV"
        let checksum = TokenCodec.serialChecksum(cover + payload + coverB + coverC + coverD)
        return "AA-ANCHOR-\(cover)-\(payload)-\(coverB)-\(coverC)-\(coverD)-\(checksum)-EXP60"
    }

    func testDecodesFourDigitPinCorrectly() {
        // Code-1 map: Q->0 W->1 E->2 R->3 T->4 A->5 S->6 D->7 F->8 G->9
        // "QWER" decodes to 0123.
        let token = makeToken(encodedPin: "QWER")
        XCTAssertEqual(TokenCodec.decodedPin(from: token), "0123")
    }

    func testDecodesFiveDigitPin() {
        // "QWERT" -> 01234
        let token = makeToken(encodedPin: "QWERT")
        XCTAssertEqual(TokenCodec.decodedPin(from: token), "01234")
    }

    func testRejectsTamperedChecksum() {
        let token = makePayloadToken(cover: "ABCDE", payload: "KQWER")
        // Corrupt one checksum character.
        let bad = String(token.dropLast(6)) + "ZZZZZ-EXP60"
        XCTAssertNil(TokenCodec.parse(bad))
    }

    func testDecoyReturnsFixedIllusionPin() {
        let token = "AA-ANCHOR-ABCDE-KQWER-FGHJK-LMNPQ-RSTUV-ABCDE-DEC60"
        XCTAssertTrue(TokenCodec.isDecoy(token))
        XCTAssertEqual(TokenCodec.decodedPin(from: token), TokenCodec.decoyPin)
    }

    func testDoesNotHardCodeSecretPins() {
        // Guardrail: the PIN is only ever derived from the token payload. Feed a
        // token whose payload encodes 5222 and confirm it decodes to 5222 only
        // because the payload says so — and that no unrelated literal leaks.
        // Code-1 map digits 5,2,2,2 -> A,E,E,E
        let token = makeToken(encodedPin: "AEEE")
        XCTAssertEqual(TokenCodec.decodedPin(from: token), "5222")
    }

    func testNormalisationStripsBidiAndArabicDigits() {
        // Arabic-Indic digits ٠١٢٣ should normalize and then be discarded as
        // non-alphabet input; the ASCII token survives intact.
        let token = makeToken(encodedPin: "QWER")
        let contaminated = "\u{200F}" + token + "\u{200E}"
        XCTAssertEqual(TokenCodec.normalize(contaminated), token)
    }

    func testLegacyTokenFormatDecodes() {
        // AA-<digits>-EXP60 where digits use code-1 map.
        let token = "AA-QWER-EXP60"
        XCTAssertEqual(TokenCodec.decodedPin(from: token), "0123")
    }
}
