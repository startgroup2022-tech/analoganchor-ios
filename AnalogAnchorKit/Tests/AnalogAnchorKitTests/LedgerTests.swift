import XCTest
@testable import AnalogAnchorKit

final class LedgerTests: XCTestCase {

    func testEarnAndDeductClampToCeilingAndFloor() {
        var state = Ledger.State()

        Ledger.earn(300, reason: "Focus", category: "focus", state: &state)
        XCTAssertEqual(state.reservePoints, 300)

        Ledger.earn(400, reason: "Bonus", category: "bonus", state: &state)
        XCTAssertEqual(state.reservePoints, Ledger.weeklyCeiling, "Reserve must clamp at 500")

        Ledger.deduct(1000, reason: "Penalty", category: "penalty", state: &state)
        XCTAssertEqual(state.reservePoints, 0, "Reserve must not go below 0")
    }

    func testDayGuardUnlockMilestoneAt150() {
        var state = Ledger.State()
        XCTAssertFalse(state.dayGuardUnlockMilestoneReached)
        Ledger.earn(150, reason: "Milestone", category: "milestone", state: &state)
        XCTAssertTrue(state.dayGuardUnlockMilestoneReached)
    }

    func testWeeklyProgressIsNormalised() {
        var state = Ledger.State()
        Ledger.earn(250, reason: "Half", category: "focus", state: &state)
        XCTAssertEqual(state.weeklyProgress, 0.5, accuracy: 0.0001)
    }

    func testFridayResetBanksReserveAndZeroes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bahrain")!
        // 2026-05-15 is a Friday.
        let friday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 5))!
        XCTAssertEqual(calendar.component(.weekday, from: friday), Ledger.resetWeekday)

        var state = Ledger.State(reservePoints: 480)
        let didReset = Ledger.performWeeklyReset(for: friday, state: &state, calendar: calendar)
        XCTAssertTrue(didReset)
        XCTAssertEqual(state.reservePoints, 0)
        XCTAssertEqual(state.bankedStakePoints, 480)
    }

    func testResetOnlyRunsOncePerFriday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bahrain")!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 5))!

        var state = Ledger.State(reservePoints: 100)
        XCTAssertTrue(Ledger.performWeeklyReset(for: friday, state: &state, calendar: calendar))
        XCTAssertFalse(Ledger.performWeeklyReset(for: friday, state: &state, calendar: calendar))
    }

    func testResetDoesNotRunOnNonFriday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bahrain")!
        // 2026-05-14 is a Thursday.
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 14, hour: 5))!
        var state = Ledger.State(reservePoints: 100)
        XCTAssertFalse(Ledger.performWeeklyReset(for: thursday, state: &state, calendar: calendar))
    }
}
