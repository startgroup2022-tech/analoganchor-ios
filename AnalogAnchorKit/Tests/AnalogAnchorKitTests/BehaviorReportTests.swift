import XCTest
@testable import AnalogAnchorKit

/// Tests for the DeviceActivityReport-backed behavior pipeline.
///
/// These cover the *portable* reduction (`BehaviorReportSnapshot.metrics`), the
/// snapshot round-trip through `SharedPolicyStore`, and the flag repository. The
/// report extension itself runs on-device only.
final class BehaviorReportTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aa-report-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSnapshotRoundTripsThroughSharedPolicyStore() {
        var store = SharedPolicyStore(directory: directory)
        let snapshot = BehaviorReportSnapshot(
            windowHours: 24,
            applications: [.init(identifier: "app", displayName: "Social", totalSeconds: 3600)],
            categories: [.init(identifier: "cat", displayName: "Social", totalSeconds: 1800)]
        )
        XCTAssertTrue(store.saveBehaviorReport(snapshot))
        let loaded = store.loadBehaviorReport()
        XCTAssertEqual(loaded?.windowHours, snapshot.windowHours)
        XCTAssertEqual(loaded?.applications, snapshot.applications)
        XCTAssertEqual(loaded?.categories, snapshot.categories)
        // Dates round-trip through JSON with sub-second loss; compare loosely.
        XCTAssertEqual(
            loaded?.generatedAt.timeIntervalSince1970 ?? 0,
            snapshot.generatedAt.timeIntervalSince1970,
            accuracy: 0.01
        )
    }

    func testMetricsScaleWindowToSevenDays() {
        // 60 min observed over a 24h window → 420 min/week estimate.
        let snapshot = BehaviorReportSnapshot(
            windowHours: 24,
            applications: [.init(identifier: "app", displayName: "Social", totalSeconds: 3600)]
        )
        let metrics = snapshot.metrics()
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics[0].appIdentifier, "Social")
        XCTAssertEqual(metrics[0].totalMinutesLast7d, 420)
    }

    func testMetricsDoNotFabricateTelemetryFields() {
        // Apple exposes durations only; open counts must never be invented.
        let snapshot = BehaviorReportSnapshot(
            windowHours: 24,
            applications: [.init(identifier: "app", displayName: "Social", totalSeconds: 10 * 3600.0)]
        )
        let metric = snapshot.metrics()[0]
        XCTAssertEqual(metric.openCountLast24h, 0)
        XCTAssertEqual(metric.compulsiveCheckCount, 0)
        XCTAssertEqual(metric.lateNightOpens, 0)
    }

    func testFreshnessWindow() {
        let fresh = BehaviorReportSnapshot(generatedAt: Date(), windowHours: 24)
        XCTAssertTrue(fresh.isFresh())

        let stale = BehaviorReportSnapshot(generatedAt: Date().addingTimeInterval(-30 * 3600), windowHours: 24)
        XCTAssertFalse(stale.isFresh())
    }

    func testUnavailableProviderNeverFabricates() async {
        let provider = UnavailableBehaviorMetricsProvider()
        XCTAssertFalse(provider.isAvailable)
        let metrics = await provider.metrics()
        XCTAssertTrue(metrics.isEmpty)
    }

    func testBehaviorFlagStorePersistsAndCounts() async {
        let store = BehaviorFlagStore(directory: directory)
        let flag = BehaviorRules.Flag(
            flagType: .heavyUsage,
            appIdentifier: "Social",
            severity: .info,
            message: "Averaged 120 minutes/day."
        )
        await store.save([flag])
        let loaded = await store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.flagType, .heavyUsage)

        let count = await store.count(of: .heavyUsage, since: Date().addingTimeInterval(-60))
        XCTAssertEqual(count, 1)
    }

    func testBehaviorFlagStoreCapsGrowth() async {
        let store = BehaviorFlagStore(directory: directory, limit: 3)
        let flags = (0..<10).map { index in
            BehaviorRules.Flag(flagType: .heavyUsage, severity: .info, message: "flag \(index)")
        }
        await store.save(flags)
        let loaded = await store.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.last?.message, "flag 9")
    }
}
