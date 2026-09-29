import XCTest
@testable import AnalogAnchorKit

/// Tests for the week-bounded streak rule ported from `calculateConsecutiveStreak`
/// and `getDaysInCurrentWeekToToday` in `AnchorViewModel.kt`.
final class WeeklyStreakTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func key(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Weekly streak rule

    func testStreakCountsBackFromTodayWhenTodayCompleted() {
        // Newest-first: today, yesterday, day-before all completed → 3
        let days = ["2026-06-05", "2026-06-04", "2026-06-03", "2026-06-02"]
        let completed: Set<String> = ["2026-06-05", "2026-06-04", "2026-06-03"]
        let streak = Streaks.weeklyStreak(weekDays: days) { completed.contains($0) }
        XCTAssertEqual(streak, 3)
    }

    func testStreakGrantsGraceFromYesterdayWhenTodayNotYetDone() {
        // Today not completed, yesterday and the day before are → streak 2.
        let days = ["2026-06-05", "2026-06-04", "2026-06-03", "2026-06-02"]
        let completed: Set<String> = ["2026-06-04", "2026-06-03"]
        let streak = Streaks.weeklyStreak(weekDays: days) { completed.contains($0) }
        XCTAssertEqual(streak, 2)
    }

    func testStreakIsZeroWhenNeitherTodayNorYesterdayCompleted() {
        let days = ["2026-06-05", "2026-06-04", "2026-06-03"]
        let completed: Set<String> = ["2026-06-03"]
        XCTAssertEqual(Streaks.weeklyStreak(weekDays: days) { completed.contains($0) }, 0)
    }

    func testStreakStopsAtFirstGap() {
        // today ✓, yesterday ✗ → 1 (the gap breaks the run)
        let days = ["2026-06-05", "2026-06-04", "2026-06-03", "2026-06-02"]
        let completed: Set<String> = ["2026-06-05", "2026-06-03", "2026-06-02"]
        XCTAssertEqual(Streaks.weeklyStreak(weekDays: days) { completed.contains($0) }, 1)
    }

    func testEmptyWeekYieldsZero() {
        XCTAssertEqual(Streaks.weeklyStreak(weekDays: []) { _ in true }, 0)
    }

    // MARK: - Week window

    func testWeekWindowRunsFromFridayToTodayMostRecentFirst() {
        // 2026-06-05 is a Friday. Then Sat 6, Sun 7, Mon 8.
        let monday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 8, hour: 12))!
        let days = Streaks.currentWeekDaysToToday(now: monday, calendar: calendar, key: key)
        XCTAssertEqual(days.first, "2026-06-08", "index 0 must be today")
        XCTAssertEqual(days.last, "2026-06-05", "the window opens on Friday")
        XCTAssertEqual(days.count, 4)
    }

    func testOnFridayTheWindowIsJustThatDay() {
        let friday = calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 12))!
        let days = Streaks.currentWeekDaysToToday(now: friday, calendar: calendar, key: key)
        XCTAssertEqual(days, ["2026-06-05"])
    }

    // MARK: - Friday reset

    func testWeeklyResetClearsEveryPillar() {
        var state = Streaks.State()
        Streaks.increment(.mosque, in: &state)
        Streaks.increment(.mosque, in: &state)   // 2
        Streaks.increment(.anchor, in: &state)   // 1
        XCTAssertEqual(state.current(.mosque), 2)
        XCTAssertEqual(state.best(.mosque), 2)

        Streaks.resetWeekly(in: &state)
        XCTAssertEqual(state.current(.mosque), 0)
        XCTAssertEqual(state.current(.anchor), 0)
        XCTAssertEqual(state.best(.mosque), 2, "best is preserved across the reset")
    }
}
