import Foundation
import AnalogAnchorKit

/// The lifecycle of a partner connection attempt, derived from real CoreBluetooth
/// callbacks. This is a presentation state only — the session/settlement rules
/// stay in `PartnerDomain`.
enum PartnerConnectionState: Equatable {
    case bluetoothUnavailable(String)
    case idle
    case scanning
    case discovered
    case connecting
    case connected
    case sessionActive
    case completed
    case cancelled
    case timedOut

    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .timedOut: return true
        default: return false
        }
    }
}

#if canImport(CoreBluetooth)
import CoreBluetooth

/// Real CoreBluetooth transport for the Partner "Circle" discovery.
///
/// Ports `PartnerPairingManager` faithfully:
/// - the same service UUID as Android (`0000AA01-…`) so iOS and Android peers
///   can find each other,
/// - the same scan-response payload layout: `[status][remainingMinutes][name]`
///   with the name capped at 11 UTF-8 bytes (the Android 31-byte limit),
/// - the same 18-second staleness window.
///
/// ## Constraints (documented, not worked around)
/// iOS cannot advertise AND scan the same service while in the background the
/// way Android could; both roles therefore run **in the foreground** while the
/// pairing sheet is open, which is exactly when the user expects them. There is
/// no attempt at a hidden background BLE session.
///
/// The API exposes a name that may be the local device name; nothing is logged.
@MainActor
final class PartnerBluetoothTransport: NSObject, ObservableObject, PartnerTransport {

    /// A partner this device has seen over BLE.
    @Published private(set) var partners: [DiscoveredPartner] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isAdvertising = false
    @Published private(set) var lastError: String?

    /// Real connection lifecycle, driven only by CoreBluetooth callbacks and the
    /// explicit user actions below. Never set optimistically.
    @Published private(set) var connectionState: PartnerConnectionState = .idle
    /// The peer currently being connected/connected to, if any.
    @Published private(set) var connectedPartner: DiscoveredPartner?

    private var central: CBCentralManager?
    private var peripheral: CBPeripheralManager?

    /// The name this device advertises (capped like Android).
    var advertisedName: String = "Analog Anchor"

    /// Status broadcast while a session is active, so peers see remaining time.
    var advertisedRemainingMinutes: Int = 60
    var advertisedHasActiveSession: Bool = false

    private let serviceUUID = CBUUID(string: AnalogAnchorConfig.partnerServiceUUID)

    /// Last-seen timestamps by peripheral id string, for the 18s staleness prune.
    private var lastSeen: [String: Date] = [:]

    /// Peripherals seen while scanning, keyed by identifier, so a discovered
    /// partner can actually be connected to.
    private var knownPeripherals: [String: CBPeripheral] = [:]

    // MARK: - PartnerTransport

    var isAvailable: Bool { CBManager.authorization != .denied }

    func startAdvertising() async {
        if peripheral == nil {
            // `CBPeripheralManager(delegate:)` starts in `.unknown`; the delegate
            // callback performs the actual advertising once state is `.poweredOn`.
            peripheral = CBPeripheralManager(delegate: self, queue: .main)
        } else if peripheral?.state == .poweredOn {
            beginAdvertising()
        }
    }

    func stopAdvertising() async {
        peripheral?.stopAdvertising()
        isAdvertising = false
    }

    func discoveredPartners() async -> [DiscoveredPartner] {
        partners
    }

    // MARK: - Scanning

    func startScanning() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScanning()
        }
    }

    func stopScanning() {
        central?.stopScan()
        isScanning = false
        if connectionState == .scanning { connectionState = .idle }
    }

    // MARK: - Connect / disconnect (real CBPeripheral lifecycle)

    /// Connects to a discovered peer. The state becomes `.connected` only when
    /// CoreBluetooth actually reports success — never optimistically.
    func connect(to partner: DiscoveredPartner) {
        guard let central, central.state == .poweredOn else {
            connectionState = .bluetoothUnavailable("Bluetooth is not powered on.")
            return
        }
        guard let peripheral = knownPeripherals[partner.id] else {
            connectionState = .timedOut
            lastError = "That partner is no longer visible. Scan again."
            return
        }
        stopScanning()
        connectedPartner = partner
        connectionState = .connecting
        central.connect(peripheral, options: nil)
    }

    /// Cancels an in-flight connection or ends an active session.
    func disconnect() {
        if let central, let id = connectedPartner?.id, let peripheral = knownPeripherals[id] {
            central.cancelPeripheralConnection(peripheral)
        }
        connectedPartner = nil
        connectionState = .cancelled
    }

    /// Marks a connected pairing as an active session (the domain owns the
    /// session itself; this only reflects it in the transport UI state).
    func markSessionActive() {
        guard connectionState == .connected else { return }
        connectionState = .sessionActive
    }

    /// Marks the session finished. Settlement is applied by `AppEnvironment`
    /// through `PartnerDomain`, not here.
    func markSessionCompleted() {
        connectionState = .completed
        connectedPartner = nil
    }

    /// Drops partners not seen recently (mirrors `pruneStaleDevices`, 18s).
    func pruneStale() {
        let cutoff = Date().addingTimeInterval(-18)
        lastSeen = lastSeen.filter { $0.value >= cutoff }
        partners = partners.filter { lastSeen[$0.id] != nil }
    }

    // MARK: - Advertising internals

    private func beginAdvertising() {
        guard let peripheral, peripheral.state == .poweredOn else { return }

        // Status + remaining-minutes payload keyed by the service UUID, matching
        // the Android scan-response layout. `startAdvertising` accepts a single
        // dictionary, so the UUID and service data go together here.
        var payload = Data()
        payload.append(advertisedHasActiveSession ? 0x01 : 0x00)
        payload.append(UInt8(clamping: advertisedRemainingMinutes))
        payload.append(Self.cappedNameBytes(advertisedName, max: AnalogAnchorConfig.partnerAdvertisedNameBytes))

        peripheral.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [serviceUUID],
            CBAdvertisementDataServiceDataKey: [serviceUUID: payload]
        ])
        isAdvertising = true
    }

    /// Truncates a name to at most `max` UTF-8 bytes without splitting a scalar.
    static func cappedNameBytes(_ name: String, max: Int) -> Data {
        var data = Data()
        for scalar in name.unicodeScalars {
            let encoded = Data(String(scalar).utf8)
            if data.count + encoded.count > max { break }
            data.append(encoded)
        }
        return data
    }

    /// Decodes a peer's scan-response payload.
    static func decodePayload(_ data: Data) -> (hasActiveSession: Bool, remainingMinutes: Int, name: String?)? {
        guard data.count >= 2 else { return nil }
        let hasActive = data[data.startIndex] == 0x01
        let remaining = Int(data[data.startIndex + 1])
        let nameData = data.dropFirst(2)
        let name = nameData.isEmpty ? nil : String(data: nameData, encoding: .utf8)
        return (hasActive, remaining, name)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension PartnerBluetoothTransport: CBPeripheralManagerDelegate {
    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            switch peripheral.state {
            case .poweredOn: self.beginAdvertising()
            case .unauthorized:
                self.lastError = "Bluetooth permission was denied."
                self.isAdvertising = false
            case .unsupported:
                self.lastError = "This device does not support Bluetooth LE."
                self.isAdvertising = false
            default:
                self.isAdvertising = false
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension PartnerBluetoothTransport: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn: self.beginScanning()
            case .unauthorized:
                self.lastError = "Bluetooth permission was denied."
                self.isScanning = false
            case .unsupported:
                self.lastError = "This device does not support Bluetooth LE."
                self.isScanning = false
            default:
                self.isScanning = false
            }
        }
    }

    private func beginScanning() {
        guard let central, central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: [serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        if !connectionState.isTerminal { connectionState = .scanning }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Only the payload we asked for; never the raw device name advertised by
        // unrelated hardware.
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let uuidKey = CBUUID(string: AnalogAnchorConfig.partnerServiceUUID)
        let payload = serviceData?[uuidKey]
        let decoded = payload.flatMap(PartnerBluetoothTransport.decodePayload)

        let partner = DiscoveredPartner(
            id: peripheral.identifier.uuidString,
            name: decoded?.name ?? "Nearby Partner",
            rssi: RSSI.intValue,
            remainingMinutes: decoded?.remainingMinutes ?? 60,
            hasActiveSession: decoded?.hasActiveSession ?? false
        )

        Task { @MainActor in
            self.lastSeen[peripheral.identifier.uuidString] = Date()
            self.knownPeripherals[peripheral.identifier.uuidString] = peripheral
            if let index = self.partners.firstIndex(where: { $0.id == partner.id }) {
                self.partners[index] = partner
            } else {
                self.partners.append(partner)
            }
            self.pruneStale()
            // A peer in range is a real discovery signal; only advertise it as
            // such when the user is not already mid-connect.
            if self.connectionState == .scanning, !self.partners.isEmpty {
                self.connectionState = .discovered
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectionState = .connected
            self.lastError = nil
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            self.connectionState = .timedOut
            self.lastError = error?.localizedDescription ?? "Could not connect to that partner."
            self.connectedPartner = nil
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            // A drop after an active session is a real, reportable event.
            if self.connectionState == .sessionActive {
                self.lastError = error?.localizedDescription ?? "The partner connection dropped."
            }
            if !self.connectionState.isTerminal {
                self.connectionState = .idle
            }
            self.connectedPartner = nil
        }
    }
}

#else

/// Non-Apple fallback so the type always exists (e.g. CI compilation / Linux).
@MainActor
final class PartnerBluetoothTransport: NSObject, ObservableObject, PartnerTransport {
    @Published private(set) var partners: [DiscoveredPartner] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isAdvertising = false
    @Published private(set) var lastError: String?
    @Published private(set) var connectionState: PartnerConnectionState = .bluetoothUnavailable("Bluetooth is unavailable in this build.")
    @Published private(set) var connectedPartner: DiscoveredPartner?
    var advertisedName = "Analog Anchor"
    var advertisedRemainingMinutes = 60
    var advertisedHasActiveSession = false

    var isAvailable: Bool { false }
    func startAdvertising() async { lastError = "Bluetooth is unavailable in this build." }
    func stopAdvertising() async {}
    func discoveredPartners() async -> [DiscoveredPartner] { [] }
    func startScanning() { lastError = "Bluetooth is unavailable in this build." }
    func stopScanning() {}
    func connect(to partner: DiscoveredPartner) { lastError = "Bluetooth is unavailable in this build." }
    func disconnect() {}
    func markSessionActive() {}
    func markSessionCompleted() {}
    func pruneStale() {}
}
#endif
