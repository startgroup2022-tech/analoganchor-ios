import XCTest
@testable import AnalogAnchorKit

/// Tests for the Fajr / nightly-discipline domain and the Partner domain.
final class FajrAndPartnerDomainTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour; c.minute = minute
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    // MARK: - Fajr proofs

    func testFajrSatisfiedByAnyProofUnlessMissed() {
        XCTAssertTrue(FajrDomain.DailyProofs(alarmDismissedInApp: true).isFajrSatisfied)
        XCTAssertTrue(FajrDomain.DailyProofs(wakeStepVerified: true).isFajrSatisfied)
        XCTAssertTrue(FajrDomain.DailyProofs(prayerVerified: true).isFajrSatisfied)
        XCTAssertFalse(FajrDomain.DailyProofs().isFajrSatisfied)
        XCTAssertFalse(FajrDomain.DailyProofs(wakeStepVerified: true, missed: true).isFajrSatisfied)
    }

    // MARK: - Sleep pressure

    func testSleepPressureThresholds() {
        XCTAssertEqual(FajrDomain.sleepPressure(timeUntilFajr: 10 * 3600, isNightWindow: false), .normal)
        XCTAssertEqual(FajrDomain.sleepPressure(timeUntilFajr: 8 * 3600, isNightWindow: true), .nightWindow)
        XCTAssertEqual(FajrDomain.sleepPressure(timeUntilFajr: 6 * 3600, isNightWindow: true), .lastWindow)
        XCTAssertEqual(FajrDomain.sleepPressure(timeUntilFajr: 5 * 3600, isNightWindow: true), .minimum)
        XCTAssertEqual(FajrDomain.sleepPressure(timeUntilFajr: 3600, isNightWindow: true), .minimum)
    }

    func testNightDisciplineWindowWrapsMidnight() {
        let fajr = date(2026, 6, 1, hour: 4)
        let isha = date(2026, 6, 1, hour: 20)
        // After Isha, before the following Fajr.
        XCTAssertTrue(FajrDomain.isNightDisciplineWindow(now: date(2026, 6, 1, hour: 23), fajr: fajr, isha: isha))
        XCTAssertTrue(FajrDomain.isNightDisciplineWindow(now: date(2026, 6, 2, hour: 2), fajr: fajr, isha: isha))
        // Daytime is outside the window.
        XCTAssertFalse(FajrDomain.isNightDisciplineWindow(now: date(2026, 6, 1, hour: 12), fajr: fajr, isha: isha))
    }

    // MARK: - Prayer windows

    func testFajrWindowRunsUntilSunrisePlusThirty() {
        let fajr = date(2026, 6, 1, hour: 4)
        let sunrise = date(2026, 6, 1, hour: 5)
        XCTAssertTrue(FajrDomain.isFajrWindowActive(now: date(2026, 6, 1, hour: 5, minute: 20), fajr: fajr, sunrise: sunrise))
        XCTAssertFalse(FajrDomain.isFajrWindowActive(now: date(2026, 6, 1, hour: 5, minute: 31), fajr: fajr, sunrise: sunrise))
    }

    func testMaghribRetreatWindowSpansFifteenBeforeToSixtyAfterIsha() {
        let maghrib = date(2026, 6, 1, hour: 18)
        let isha = date(2026, 6, 1, hour: 19, minute: 30)
        XCTAssertTrue(FajrDomain.isMaghribRetreatWindowActive(now: date(2026, 6, 1, hour: 17, minute: 50), maghrib: maghrib, isha: isha))
        XCTAssertTrue(FajrDomain.isMaghribRetreatWindowActive(now: date(2026, 6, 1, hour: 20, minute: 25), maghrib: maghrib, isha: isha))
        XCTAssertFalse(FajrDomain.isMaghribRetreatWindowActive(now: date(2026, 6, 1, hour: 20, minute: 35), maghrib: maghrib, isha: isha))
    }

    func testJumuahMissCheckOnlyOnFridayAfterTwoPM() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        // 2026-06-05 is a Friday.
        XCTAssertTrue(FajrDomain.isJumuahMissCheckDue(now: date(2026, 6, 5, hour: 14), calendar: cal))
        XCTAssertFalse(FajrDomain.isJumuahMissCheckDue(now: date(2026, 6, 5, hour: 13), calendar: cal))
        XCTAssertFalse(FajrDomain.isJumuahMissCheckDue(now: date(2026, 6, 4, hour: 15), calendar: cal)) // Thursday
    }

    // MARK: - Wake step tracker

    func testWakeStepTrackerProvesWakeAtGoal() {
        var tracker = FajrDomain.WakeStepTracker()
        tracker.arm(baseline: nil)
        XCTAssertFalse(tracker.update(cumulativeSteps: 1000), "first sample establishes the baseline")
        XCTAssertEqual(tracker.baseline, 1000)
        XCTAssertFalse(tracker.update(cumulativeSteps: 1001))
        XCTAssertEqual(tracker.stepsAfterDismiss, 1)
        XCTAssertTrue(tracker.update(cumulativeSteps: 1002), "second step reaches the goal")
        XCTAssertFalse(tracker.isActive)
    }

    func testWakeStepTrackerDetectorVariant() {
        var tracker = FajrDomain.WakeStepTracker()
        tracker.arm(baseline: 0)
        XCTAssertFalse(tracker.recordDetectorStep())
        XCTAssertTrue(tracker.recordDetectorStep())
        XCTAssertFalse(tracker.isActive)
    }

    // MARK: - Partner

    func testPendingSessionExpiresAfterGraceWindow() {
        let start = date(2026, 6, 1, hour: 12)
        let session = PartnerDomain.Session(status: .pending, startedAt: start)
        XCTAssertFalse(session.isExpired(now: start.addingTimeInterval(4 * 60)))
        XCTAssertTrue(session.isExpired(now: start.addingTimeInterval(6 * 60)))
    }

    func testActiveSessionExpiresAtScheduledEnd() {
        let start = date(2026, 6, 1, hour: 12)
        let session = PartnerDomain.Session(status: .active, startedAt: start, durationMinutes: 60)
        XCTAssertFalse(session.isExpired(now: start.addingTimeInterval(59 * 60)))
        XCTAssertTrue(session.isExpired(now: start.addingTimeInterval(61 * 60)))
    }

    func testExpiredPendingSessionYieldsCovenantPenalty() {
        let start = date(2026, 6, 1, hour: 12)
        let session = PartnerDomain.Session(status: .pending, startedAt: start)
        let settlement = PartnerDomain.settlementForExpiredPendingSession(session, now: start.addingTimeInterval(6 * 60))
        XCTAssertEqual(settlement?.points, -PartnerDomain.brokeCovenantPenalty)
        XCTAssertEqual(settlement?.status, "penalty")
    }

    func testCompletionRewardSoloVersusGroup() {
        let solo = PartnerDomain.settleCompletion(isSuccess: true, isGroup: false, partnerName: "Aisha", durationMinutes: 60)
        XCTAssertEqual(solo.points, PartnerDomain.partnerCompletionPoints)
        XCTAssertTrue(solo.incrementsPartnerQuota)

        let group = PartnerDomain.settleCompletion(isSuccess: true, isGroup: true, partnerName: "Circle", durationMinutes: 60)
        XCTAssertEqual(group.points, PartnerDomain.groupCompletionPoints)
    }

    func testCompletionFailureAppliesBrokenOutingPenalty() {
        let failure = PartnerDomain.settleCompletion(isSuccess: false, isGroup: false, partnerName: "Aisha", durationMinutes: 60)
        XCTAssertEqual(failure.points, -PartnerDomain.brokenOutingPenalty)
        XCTAssertFalse(failure.incrementsPartnerQuota)
    }

    func testConfirmActivationPromotesPendingToActive() {
        var session = PartnerDomain.Session(status: .pending)
        PartnerDomain.confirmActivation(&session, partnerName: "Yusuf", durationMinutes: 90, startTime: nil, sessionId: "abc")
        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(session.partnerName, "Yusuf")
        XCTAssertEqual(session.durationMinutes, 90)
        XCTAssertEqual(session.id, "abc")
    }
}
