import XCTest
@testable import AnalogAnchorKit

final class PoliciesTests: XCTestCase {

    func testTimeWindowContainsAndCrossesMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bahrain")!

        let bedtime = Policies.TimeWindow(start: "22:00", end: "07:00")!
        XCTAssertTrue(bedtime.crossesMidnight)

        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 23))!
        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 5, day: 16, hour: 6))!
        let midday = calendar.date(from: DateComponents(year: 2026, month: 5, day: 16, hour: 12))!

        XCTAssertTrue(bedtime.contains(lateNight, calendar: calendar))
        XCTAssertTrue(bedtime.contains(earlyMorning, calendar: calendar))
        XCTAssertFalse(bedtime.contains(midday, calendar: calendar))
    }

    func testDefaultDailyLimitIsSixtyWhenUnset() {
        XCTAssertEqual(Policies.effectiveDailyLimit(nil), 60)
        XCTAssertEqual(Policies.effectiveDailyLimit(0), 60)
        XCTAssertEqual(Policies.effectiveDailyLimit(-5), 60)
        XCTAssertEqual(Policies.effectiveDailyLimit(30), 30)
    }

    func testAvailableDurationsAreClampedToRemaining() {
        XCTAssertEqual(Policies.availableDurations(remainingMinutes: 5), [2, 5])
        XCTAssertEqual(Policies.availableDurations(remainingMinutes: 3), [2])
        XCTAssertEqual(Policies.availableDurations(remainingMinutes: 1), [1])
        XCTAssertTrue(Policies.availableDurations(remainingMinutes: 0).isEmpty)
        XCTAssertEqual(Policies.availableDurations(remainingMinutes: 100), [2, 5, 10, 30])
    }

    func testPolicyEditWindowClosesAtFivePM() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bahrain")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 12))!
        let evening = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 18))!
        XCTAssertTrue(Policies.isPolicyEditWindowOpen(now: noon, calendar: calendar))
        XCTAssertFalse(Policies.isPolicyEditWindowOpen(now: evening, calendar: calendar))
    }

    func testSoftLandingExcludesIsha() {
        XCTAssertFalse(Policies.softLandingPrayers.contains("isha"))
        XCTAssertTrue(Policies.softLandingPrayers.contains("dhuhr"))
        XCTAssertTrue(Policies.softLandingPrayers.contains("asr"))
        XCTAssertTrue(Policies.softLandingPrayers.contains("maghrib"))
    }
}
