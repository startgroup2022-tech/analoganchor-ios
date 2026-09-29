import XCTest
@testable import AnalogAnchorKit

/// Tests for the Stake / Covenant domain ported from `AnchorViewModel.kt`.
final class StakeCovenantTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = hour
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    // MARK: - Stake

    func testStakeWeekIsOneOnInstallDay() {
        let state = Stake.calculate(
            installDate: date(2026, 1, 1),
            now: date(2026, 1, 1, hour: 5),
            bankedStakePoints: 0,
            reservePoints: 100
        )
        XCTAssertEqual(state.week, 1)
        XCTAssertEqual(state.totalCumulativePoints, 100)
    }

    func testStakeWeekAdvancesEverySevenDaysAndCapsAtTwelve() {
        let install = date(2026, 1, 1)
        // Day 7 → (7/7)+1 = 2
        XCTAssertEqual(Stake.calculate(installDate: install, now: date(2026, 1, 8), bankedStakePoints: 0, reservePoints: 0).week, 2)
        // Day 77 → (77/7)+1 = 12
        XCTAssertEqual(Stake.calculate(installDate: install, now: date(2026, 3, 19), bankedStakePoints: 0, reservePoints: 0).week, 12)
        // Day 140 → would be 21, clamped to 12
        XCTAssertEqual(Stake.calculate(installDate: install, now: date(2026, 5, 21), bankedStakePoints: 0, reservePoints: 0).week, 12)
    }

    func testStakePercentageUses6000TargetAndIgnoresNegativeReserve() {
        let state = Stake.calculate(
            installDate: date(2026, 1, 1),
            now: date(2026, 1, 1),
            bankedStakePoints: 600,
            reservePoints: -50 // coerceAtLeast(0)
        )
        XCTAssertEqual(state.totalCumulativePoints, 600)
        XCTAssertEqual(state.cumulativePercentage, 10.0, accuracy: 0.0001)
    }

    func testStakePercentageCanExceedOneHundred() {
        let state = Stake.calculate(
            installDate: date(2026, 1, 1),
            now: date(2026, 1, 1),
            bankedStakePoints: 6000,
            reservePoints: 600
        )
        XCTAssertEqual(state.cumulativePercentage, 110.0, accuracy: 0.0001)
    }

    // MARK: - Covenant

    func testCovenantDayNumberClampsBetweenOneAndForty() {
        let start = date(2026, 1, 1)
        XCTAssertEqual(Covenant.calculate(startDate: start, now: start, evidence: []).dayNumber, 1)
        XCTAssertEqual(Covenant.calculate(startDate: start, now: date(2026, 3, 1), evidence: []).dayNumber, 40)
    }

    func testCovenantScoreSumsMosqueFajrAndOutdoor() {
        let start = date(2026, 1, 1)
        var day1 = Covenant.DayEvidence()
        day1.verifiedMosquePrayers = ["dhuhr", "asr"]      // 2 * 40 = 80
        day1.fajrWakeVerified = true                        // +40
        day1.outdoorSessionCount = 2                        // +2 * 15 = 30
        let state = Covenant.calculate(
            startDate: start,
            now: date(2026, 1, 1),
            evidence: [day1]
        )
        XCTAssertEqual(state.score, 150)
    }

    func testCovenantFajrMissedCancelsAllFajrProofs() {
        let start = date(2026, 1, 1)
        var day1 = Covenant.DayEvidence()
        day1.fajrMosqueVerified = true
        day1.fajrWakeVerified = true
        day1.fajrPrayerVerified = true
        day1.fajrMissed = true                              // overrides all
        let state = Covenant.calculate(startDate: start, now: start, evidence: [day1])
        XCTAssertEqual(state.score, 0)
    }

    func testCovenantIgnoresUnknownPrayerKeys() {
        let start = date(2026, 1, 1)
        var day1 = Covenant.DayEvidence()
        day1.verifiedMosquePrayers = ["dhuhr", "tahajjud", "witr"]  // only dhuhr counts
        let state = Covenant.calculate(startDate: start, now: start, evidence: [day1])
        XCTAssertEqual(state.score, Covenant.prayerPoints)
    }

    func testCovenantScoreCapsAt8000AndPercentageAtHundred() {
        let start = date(2026, 1, 1)
        let heavy = Covenant.DayEvidence(verifiedMosquePrayers: ["dhuhr", "asr", "maghrib", "isha"], outdoorSessionCount: 100)
        let evidence = Array(repeating: heavy, count: 40)
        let state = Covenant.calculate(startDate: start, now: date(2026, 3, 1), evidence: evidence)
        XCTAssertEqual(state.score, Covenant.scoreCeiling)
        XCTAssertEqual(state.percentage, 100)
    }

    func testCovenantMilestoneBonusRequiresDay40And6000() {
        let notReady = Covenant.State(dayNumber: 40, score: 5999)
        XCTAssertNil(Covenant.claimMilestoneBonus(state: notReady))

        let ready = Covenant.State(dayNumber: 40, score: 6000)
        XCTAssertEqual(Covenant.claimMilestoneBonus(state: ready), Covenant.milestoneBonusPoints)

        let tooEarly = Covenant.State(dayNumber: 39, score: 8000)
        XCTAssertNil(Covenant.claimMilestoneBonus(state: tooEarly))
    }

    func testCovenantMilestoneBonusIsClaimedOnlyOnce() {
        let claimed = Covenant.State(dayNumber: 40, score: 8000, bonusClaimed: true)
        XCTAssertNil(Covenant.claimMilestoneBonus(state: claimed))
    }
}
