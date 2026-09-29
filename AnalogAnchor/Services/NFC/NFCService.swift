import Foundation
import AnalogAnchorKit

#if canImport(CoreNFC)
import CoreNFC

/// CoreNFC reader/writer for the physical Anchor architecture.
///
/// The Android app used reader-mode NFC with two private MIME types
/// (`…anchor` / `…fajr`). iOS cannot background-scan NFC the way Android can,
/// so here the reader session is started explicitly by the user from the Anchor
/// or Fajr flows — the same physical act, triggered from the foreground.
///
/// Requires `com.apple.developer.nfc.readersession.formats = TAG` and
/// `NFCReaderUsageDescription`.
@MainActor
final class NFCService: NSObject, ObservableObject, NFCProviding {

    @Published private(set) var lastTagID: String?
    @Published private(set) var isScanning = false
    @Published private(set) var lastError: String?

    /// Called with the scanned tag id + its routing MIME (anchor/fajr).
    var onTagScanned: ((String, String?) -> Void)?

    private var session: NFCNDEFReaderSession?
    private var readContinuation: CheckedContinuation<String?, Never>?

    var isSupported: Bool { NFCNDEFReaderSession.readingAvailable }

    /// Starts a foreground NFC scan. The session returns the tag id and, when
    /// present, the private Analog Anchor MIME type used for routing.
    func beginScanning() {
        lastError = nil
        guard NFCNDEFReaderSession.readingAvailable else {
            lastError = "NFC is not available on this device."
            return
        }
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session.alertMessage = "Hold the top of your iPhone near the Anchor tag."
        self.session = session
        isScanning = true
        session.begin()
    }

    func cancelScanning() {
        session?.invalidate()
        session = nil
        isScanning = false
        resumeRead(with: nil)
    }

    /// Async one-shot scan returning the tag id (used by the Fajr / Anchor flows).
    func scanTag(message: String? = nil) async -> String? {
        guard isSupported else {
            lastError = "NFC is not available on this device."
            return nil
        }
        lastError = nil
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session.alertMessage = message ?? "Hold the top of your iPhone near the Anchor tag."
        self.session = session
        isScanning = true
        return await withCheckedContinuation { continuation in
            self.readContinuation = continuation
            session.begin()
        }
    }

    private func resumeRead(with value: String?) {
        guard let continuation = readContinuation else { return }
        readContinuation = nil
        continuation.resume(returning: value)
    }

    // MARK: - Tag id extraction

    static func hexID(from tag: NFCNDEFTag) -> String? {
        guard let concrete = tag as? NFCTag else { return nil }
        switch concrete {
        case .miFare(let t): return t.identifier.map { String(format: "%02X", $0) }.joined(separator: ":")
        case .iso15693(let t): return t.identifier.map { String(format: "%02X", $0) }.joined(separator: ":")
        case .iso7816(let t): return t.identifier.map { String(format: "%02X", $0) }.joined(separator: ":")
        case .feliCa(let t): return t.currentIDm.map { String(format: "%02X", $0) }.joined(separator: ":")
        @unknown default: return nil
        }
    }
}

extension NFCService: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false
            if let readerError = error as? NFCReaderError,
               readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead,
               readerError.code != .readerSessionInvalidationErrorUserCanceled {
                self.lastError = readerError.localizedDescription
            }
            // Always resolve a pending async read so callers never hang.
            self.resumeRead(with: nil)
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Handled in didDetect(tags:) below.
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag detected.")
            return
        }
        let tagID = NFCService.hexID(from: tag)
        var mimeType: String?
        if let ndefTag = tag as? NFCNDEFTag {
            // Best-effort: read the first record's type for routing.
            ndefTag.readNDEF { message, _ in
                if let record = message?.records.first,
                   record.typeNameFormat == .media,
                   let type = String(data: record.type, encoding: .utf8) {
                    mimeType = type
                }
                session.alertMessage = "Anchor recognised."
                session.invalidate()
                Task { @MainActor in
                    self.lastTagID = tagID
                    self.isScanning = false
                    if let tagID {
                        self.onTagScanned?(tagID, mimeType)
                    }
                    self.resumeRead(with: tagID)
                }
            }
        } else {
            session.invalidate()
            Task { @MainActor in
                self.lastTagID = tagID
                self.isScanning = false
                if let tagID { self.onTagScanned?(tagID, nil) }
                self.resumeRead(with: tagID)
            }
        }
    }
}
#else

/// Non-Apple fallback so the type always exists (e.g. CI compilation).
@MainActor
final class NFCService: NSObject, ObservableObject {
    @Published private(set) var lastTagID: String?
    @Published private(set) var isScanning = false
    @Published private(set) var lastError: String?
    var onTagScanned: ((String, String?) -> Void)?
    var isSupported: Bool { false }
    func beginScanning() { lastError = "NFC is unavailable in this build." }
    func cancelScanning() {}
    func scanTag(message: String? = nil) async -> String? {
        lastError = "NFC is unavailable in this build."
        return nil
    }
}
#endif
