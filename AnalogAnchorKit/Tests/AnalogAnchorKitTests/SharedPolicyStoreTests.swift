import XCTest
@testable import AnalogAnchorKit

final class SharedPolicyStoreTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aa-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() -> SharedPolicyStore {
        SharedPolicyStore(directory: directory)
    }

    func testPolicyRoundTrip() {
        var store = makeStore()
        let original = ScreenTimePolicy(isEnabled: true, rules: [
            .init(kind: .dailyLimit, name: "Social", dailyLimitMinutes: 30),
            .init(kind: .window, name: "Bed", startMinutes: 22 * 60, endMinutes: 7 * 60)
        ])
        XCTAssertTrue(store.savePolicy(original))
        XCTAssertEqual(store.loadPolicy(), original)
    }

    func testSelectionRoundTrip() {
        var store = makeStore()
        let payload = ScreenTimeSelectionPayload(
            rawSelectionJSON: Data("{\"applications\":[]}".utf8),
            applicationCount: 3, categoryCount: 1, webDomainCount: 0
        )
        XCTAssertTrue(store.saveSelection(payload))
        XCTAssertEqual(store.loadSelection(), payload)
    }

    func testSelectionDefaultsToEmptyWhenMissing() {
        XCTAssertEqual(makeStore().loadSelection(), .empty)
        XCTAssertNil(makeStore().loadPolicy())
    }

    func testDiagnosticsAppendAndCap() {
        var store = makeStore()
        for index in 0..<60 {
            store.appendDiagnostic(.init(severity: .warning, source: "test", message: "n\(index)"))
        }
        let records = store.loadDiagnostics()
        XCTAssertEqual(records.count, 50)
        XCTAssertEqual(records.last?.message, "n59")
    }

    func testClearDiagnostics() {
        var store = makeStore()
        store.appendDiagnostic(.init(severity: .error, source: "test", message: "boom"))
        XCTAssertEqual(store.loadDiagnostics().count, 1)
        store.clearDiagnostics()
        XCTAssertTrue(store.loadDiagnostics().isEmpty)
    }

    func testDateRoundTripsExactly() {
        var store = makeStore()
        let instant = Date(timeIntervalSince1970: 1_700_000_000.25)
        let policy = ScreenTimePolicy(isEnabled: false, rules: [], updatedAt: instant)
        XCTAssertTrue(store.savePolicy(policy))
        // Plain-second dates survive the JSON round-trip exactly.
        XCTAssertEqual(store.loadPolicy()?.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testSaveReportsFailureWhenDirectoryUnwritable() {
        // A store pointed at a path that cannot be created must report the
        // failure instead of silently pretending the write succeeded.
        var bad = SharedPolicyStore(directory: URL(fileURLWithPath: "/proc/nonexistent/aa"))
        XCTAssertFalse(bad.savePolicy(ScreenTimePolicy(isEnabled: true)))
        XCTAssertNotNil(bad.lastError)
    }

    func testEngineStateRoundTrip() {
        var store = makeStore()
        let ruleID = UUID()
        XCTAssertTrue(store.saveEngineState(.init(activeCause: .dailyLimit(ruleID: ruleID), updatedAt: Date())))
        XCTAssertEqual(store.loadEngineState()?.activeCause, .dailyLimit(ruleID: ruleID))
        store.saveEngineState(.idle)
        XCTAssertNil(store.loadEngineState()?.activeCause)
    }
}
