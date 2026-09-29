import XCTest
@testable import AnalogAnchorKit

/// Tests for `BehaviorRules` (ported from Android's `BehaviorRuleEngine`) and the
/// `EmergencyDomain` token-freshness rules.
final class BehaviorAndEmergencyTests: XCTestCase {

    // MARK: - Behavior rules

    func testCompulsiveCheckerFlagThresholds() {
        // openCount >= 8 AND compulsiveCheckCount >= 3
        let borderline = BehaviorRules.Metrics(appIdentifier: "com.x", openCountLast24h: 8, compulsiveCheckCount: 3)
        let flags = BehaviorRules.evaluate(borderline)
        XCTAssertTrue(flags.contains { $0.flagType == .compulsiveChecker })

        let belowOpenCount = BehaviorRules.Metrics(appIdentifier: "com.x", openCountLast24h: 7, compulsiveCheckCount: 3)
        XCTAssertFalse(BehaviorRules.evaluate(belowOpenCount).contains { $0.flagType == .compulsiveChecker })
    }

    func testLateNightFlagRequiresThreeOpens() {
        let two = BehaviorRules.Metrics(appIdentifier: "com.x", lateNightOpens: 2)
        let three = BehaviorRules.Metrics(appIdentifier: "com.x", lateNightOpens: 3)
        XCTAssertFalse(BehaviorRules.evaluate(two).contains { $0.flagType == .lateNightPattern })
        XCTAssertTrue(BehaviorRules.evaluate(three).contains { $0.flagType == .lateNightPattern })
    }

    func testHeavyUsageUsesDailyAverageAboveNinety() {
        // 630/7 = 90 → not flagged (strictly greater than 90 required)
        let ninety = BehaviorRules.Metrics(appIdentifier: "com.x", totalMinutesLast7d: 630)
        XCTAssertFalse(BehaviorRules.evaluate(ninety).contains { $0.flagType == .heavyUsage })

        // 700/7 = 100 → flagged
        let hundred = BehaviorRules.Metrics(appIdentifier: "com.x", totalMinutesLast7d: 700)
        XCTAssertTrue(BehaviorRules.evaluate(hundred).contains { $0.flagType == .heavyUsage })
    }

    func testStreakRewardFlagOnlyWhenStreakAndNotRecentlyRewarded() {
        let withReward = BehaviorRules.evaluateAll(metrics: [], currentStreak: 7, hasRecentStreakReward: true)
        XCTAssertFalse(withReward.contains { $0.flagType == .streakReward })

        let flagged = BehaviorRules.evaluateAll(metrics: [], currentStreak: 7, hasRecentStreakReward: false)
        XCTAssertTrue(flagged.contains { $0.flagType == .streakReward })

        let shortStreak = BehaviorRules.evaluateAll(metrics: [], currentStreak: 6, hasRecentStreakReward: false)
        XCTAssertFalse(shortStreak.contains { $0.flagType == .streakReward })
    }

    func testUnavailableProviderReportsNoMetrics() async {
        let provider = UnavailableBehaviorMetricsProvider()
        XCTAssertFalse(provider.isAvailable)
        let metrics = await provider.metrics()
        XCTAssertTrue(metrics.isEmpty, "never fabricates usage data")
    }

    func testInMemoryRepositoryCountsByTypeAndDate() async {
        let old = BehaviorRules.Flag(flagType: .heavyUsage, severity: .info, message: "old", createdAt: Date(timeIntervalSince1970: 0))
        let recent = BehaviorRules.Flag(flagType: .streakReward, severity: .info, message: "new", createdAt: Date())
        let repo = InMemoryBehaviorRuleRepository(seed: [old, recent])

        let streakCount = await repo.count(of: .streakReward, since: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(streakCount, 1)
        let allLoaded = await repo.load()
        XCTAssertEqual(allLoaded.count, 2)
    }

    func testEvaluationPassIsNoOpWhenProviderUnavailable() async {
        let evaluation = BehaviorRuleEvaluation(
            provider: UnavailableBehaviorMetricsProvider(),
            repository: InMemoryBehaviorRuleRepository()
        )
        XCTAssertFalse(evaluation.isAvailable)
        let flags = await evaluation.run(currentStreak: 30, hasRecentStreakReward: false)
        XCTAssertTrue(flags.isEmpty, "must not fabricate usage or flags")
    }

    // MARK: - Emergency

    func testTokenFreshWithinSixtyMinutes() {
        let start = Date()
        XCTAssertTrue(EmergencyDomain.isTokenFresh(requestStart: start, now: start.addingTimeInterval(59 * 60)))
        XCTAssertTrue(EmergencyDomain.isTokenFresh(requestStart: start, now: start.addingTimeInterval(60 * 60)))
        XCTAssertFalse(EmergencyDomain.isTokenFresh(requestStart: start, now: start.addingTimeInterval(61 * 60)))
        XCTAssertFalse(EmergencyDomain.isTokenFresh(requestStart: nil))
    }

    func testValidTokenSuspendsShield() {
        let start = Date()
        let result = EmergencyDomain.evaluate(decodedSuccessfully: true, isDecoy: false, requestStart: start, now: start.addingTimeInterval(60))
        XCTAssertEqual(result.kind, .token)
        XCTAssertTrue(result.shouldSuspendShield)
        XCTAssertEqual(result.unlockedUntil, start.addingTimeInterval(60).addingTimeInterval(EmergencyDomain.activeUnlockDuration))
    }

    func testDecoyTokenNeverSuspendsShield() {
        let result = EmergencyDomain.evaluate(decodedSuccessfully: true, isDecoy: true, requestStart: Date(), now: Date())
        XCTAssertEqual(result.kind, .decoy)
        XCTAssertFalse(result.shouldSuspendShield, "a decoy must not clear a real shield")
    }

    func testExpiredRequestRejectsToken() {
        let start = Date()
        let result = EmergencyDomain.evaluate(
            decodedSuccessfully: true,
            isDecoy: false,
            requestStart: start,
            now: start.addingTimeInterval(61 * 60)
        )
        XCTAssertEqual(result.kind, .rejected)
        XCTAssertFalse(result.shouldSuspendShield)
    }

    func testInvalidDecodeRejects() {
        let result = EmergencyDomain.evaluate(decodedSuccessfully: false, isDecoy: false, requestStart: Date(), now: Date())
        XCTAssertEqual(result.kind, .rejected)
    }

    func testCooldownCompletion() {
        let start = Date()
        XCTAssertFalse(EmergencyDomain.isCooldownComplete(cooldownStart: start, now: start.addingTimeInterval(60)))
        XCTAssertTrue(EmergencyDomain.isCooldownComplete(cooldownStart: start, now: start.addingTimeInterval(EmergencyDomain.cooldownDuration)))
        XCTAssertEqual(EmergencyDomain.coolingRemaining(cooldownStart: start, now: start), Int(EmergencyDomain.cooldownDuration))
    }
}
