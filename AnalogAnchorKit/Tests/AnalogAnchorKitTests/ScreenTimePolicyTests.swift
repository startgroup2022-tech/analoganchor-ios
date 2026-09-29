import XCTest
@testable import AnalogAnchorKit

final class ScreenTimePolicyTests: XCTestCase {

    // MARK: - Helpers

    /// Calendar pinned to a fixed time zone (Asia/Bahrain, UTC+3) so window
    /// assertions are deterministic regardless of the host machine.
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Bahrain")!
        return c
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: - Policy creation / removal

    func testCreateDailyLimitRuleAndDeriveEffectiveLimit() {
        let rule = ScreenTimePolicy.Rule(kind: .dailyLimit, name: "Social", dailyLimitMinutes: 30)
        XCTAssertNoThrow(try ScreenTimePolicy.validate(rule))

        var policy = ScreenTimePolicy(isEnabled: true)
        policy.rules.append(rule)
        XCTAssertEqual(policy.effectiveDailyLimitMinutes, 30)
        XCTAssertEqual(policy.dailyLimitRules.count, 1)
    }

    func testEffectiveLimitIsTheStrictestConfiguredValue() {
        let policy = ScreenTimePolicy(isEnabled: true, rules: [
            .init(kind: .dailyLimit, name: "A", dailyLimitMinutes: 60),
            .init(kind: .dailyLimit, name: "B", dailyLimitMinutes: 15)
        ])
        XCTAssertEqual(policy.effectiveDailyLimitMinutes, 15)
    }

    func testEffectiveLimitFallsBackToDefaultWhenNoRule() {
        let policy = ScreenTimePolicy(isEnabled: true)
        XCTAssertEqual(policy.effectiveDailyLimitMinutes, AnalogAnchorConfig.defaultProtectedAppDailyLimitMinutes)
    }

    func testRemovingARuleUpdatesDerivedState() {
        var policy = ScreenTimePolicy(isEnabled: true, rules: [
            .init(kind: .dailyLimit, name: "A", dailyLimitMinutes: 15)
        ])
        policy.rules.removeAll()
        XCTAssertEqual(policy.effectiveDailyLimitMinutes, AnalogAnchorConfig.defaultProtectedAppDailyLimitMinutes)
    }

    func testDisabledRuleIsIgnored() {
        let policy = ScreenTimePolicy(isEnabled: true, rules: [
            .init(kind: .dailyLimit, name: "A", dailyLimitMinutes: 5, isEnabled: false)
        ])
        XCTAssertEqual(policy.activeRules.count, 0)
        XCTAssertEqual(policy.effectiveDailyLimitMinutes, AnalogAnchorConfig.defaultProtectedAppDailyLimitMinutes)
    }

    // MARK: - Multiple applications / categories

    func testSelectionPayloadCounts() {
        let payload = ScreenTimeSelectionPayload(
            rawSelectionJSON: Data("[]".utf8),
            applicationCount: 4,
            categoryCount: 2,
            webDomainCount: 1
        )
        XCTAssertFalse(payload.isEmpty)
        XCTAssertEqual(payload.applicationCount, 4)
    }

    func testEmptySelectionIsEmpty() {
        XCTAssertTrue(ScreenTimeSelectionPayload.empty.isEmpty)
    }

    // MARK: - Daily schedule validation

    func testInvalidDailyLimitRejected() {
        XCTAssertThrowsError(try ScreenTimePolicy.validate(.init(kind: .dailyLimit, name: "X", dailyLimitMinutes: 0))) {
            XCTAssertEqual($0 as? ScreenTimePolicy.ValidationError, .dailyLimitOutOfRange(0))
        }
        XCTAssertThrowsError(try ScreenTimePolicy.validate(.init(kind: .dailyLimit, name: "X", dailyLimitMinutes: 25 * 60)))
    }

    func testWindowMissingBoundsRejected() {
        XCTAssertThrowsError(try ScreenTimePolicy.validate(.init(kind: .window, name: "Bed", startMinutes: 60))) {
            XCTAssertEqual($0 as? ScreenTimePolicy.ValidationError, .windowMissingBounds)
        }
    }

    func testWindowOutOfRangeRejected() {
        XCTAssertThrowsError(try ScreenTimePolicy.validate(.init(kind: .window, name: "Bed", startMinutes: -1, endMinutes: 60)))
        XCTAssertThrowsError(try ScreenTimePolicy.validate(.init(kind: .window, name: "Bed", startMinutes: 60, endMinutes: 24 * 60 + 5)))
    }

    func testValidateWholePolicy() {
        let valid = ScreenTimePolicy(isEnabled: true, rules: [
            .init(kind: .dailyLimit, name: "Social", dailyLimitMinutes: 30),
            .init(kind: .window, name: "Bed", startMinutes: 22 * 60, endMinutes: 7 * 60)
        ])
        XCTAssertNoThrow(try ScreenTimePolicy.validate(valid))

        let invalid = ScreenTimePolicy(isEnabled: true, rules: [
            .init(kind: .dailyLimit, name: "Bad", dailyLimitMinutes: -5)
        ])
        XCTAssertThrowsError(try ScreenTimePolicy.validate(invalid))
    }

    // MARK: - Bedtime / midnight crossing

    func testBedtimeWindowCrossesMidnight() {
        let rule = ScreenTimePolicy.Rule(kind: .window, name: "Bed", startMinutes: 22 * 60, endMinutes: 7 * 60)
        XCTAssertTrue(rule.crossesMidnight)

        let policy = ScreenTimePolicy(isEnabled: true, rules: [rule])
        XCTAssertTrue(policy.isBlockedByWindow(date(2026, 3, 10, 23, 30), calendar: calendar))
        XCTAssertTrue(policy.isBlockedByWindow(date(2026, 3, 11, 3, 0), calendar: calendar))
        XCTAssertFalse(policy.isBlockedByWindow(date(2026, 3, 11, 9, 0), calendar: calendar))
    }

    func testNonCrossingWindowBoundsAreHalfOpen() {
        let rule = ScreenTimePolicy.Rule(kind: .window, name: "WindDown", startMinutes: 21 * 60 + 30, endMinutes: 22 * 60 + 30)
        XCTAssertFalse(rule.crossesMidnight)

        let policy = ScreenTimePolicy(isEnabled: true, rules: [rule])
        XCTAssertTrue(policy.isBlockedByWindow(date(2026, 3, 10, 21, 30), calendar: calendar))
        XCTAssertTrue(policy.isBlockedByWindow(date(2026, 3, 10, 22, 29), calendar: calendar))
        XCTAssertFalse(policy.isBlockedByWindow(date(2026, 3, 10, 22, 30), calendar: calendar))
        XCTAssertFalse(policy.isBlockedByWindow(date(2026, 3, 10, 21, 29), calendar: calendar))
    }

    func testWindowRespectsConfiguredWeekdays() {
        // Sunday=1 … Friday=6. Window applies to Friday only.
        let rule = ScreenTimePolicy.Rule(
            kind: .window,
            name: "Friday Wind-down",
            startMinutes: 22 * 60,
            endMinutes: 7 * 60,
            weekdays: [.friday]
        )
        let policy = ScreenTimePolicy(isEnabled: true, rules: [rule])

        // Friday 2026-03-13 at 23:00 → blocked.
        XCTAssertTrue(policy.isBlockedByWindow(date(2026, 3, 13, 23, 0), calendar: calendar))
        // Saturday 2026-03-14 at 03:00 (tail of Friday's window) → blocked.
        XCTAssertTrue(policy.isBlockedByWindow(date(2026, 3, 14, 3, 0), calendar: calendar))
        // Saturday 2026-03-14 at 23:00 → not blocked (window belongs to Friday).
        XCTAssertFalse(policy.isBlockedByWindow(date(2026, 3, 14, 23, 0), calendar: calendar))
    }

    // MARK: - Time-zone handling

    func testWindowEvaluatesInProvidedCalendarTimeZone() {
        let rule = ScreenTimePolicy.Rule(kind: .window, name: "Bed", startMinutes: 22 * 60, endMinutes: 7 * 60)
        let policy = ScreenTimePolicy(isEnabled: true, rules: [rule])

        // 2026-03-10 22:30 in Bahrain (UTC+3) == 19:30 UTC — must be blocked when
        // evaluated in the Bahrain calendar even though UTC says otherwise.
        let instant = date(2026, 3, 10, 22, 30)
        XCTAssertTrue(policy.isBlockedByWindow(instant, calendar: calendar))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertFalse(policy.isBlockedByWindow(instant, calendar: utc))
    }

    // MARK: - Friday reset interaction

    func testFridayEditLockIsClosedAfter17() {
        let lockdown = date(2026, 3, 13, 17, 0)  // Friday 17:00
        XCTAssertFalse(Policies.isPolicyEditWindowOpen(now: lockdown, calendar: calendar))
        XCTAssertTrue(Policies.isPolicyEditWindowOpen(now: date(2026, 3, 13, 16, 59), calendar: calendar))
    }

    // MARK: - Authorization state handling

    func testAuthorizationStatusRoundTripsThroughPreferences() {
        for status in [ScreenTimeAuthorizationStatus.notDetermined, .approved, .denied, .unavailable] {
            XCTAssertEqual(ScreenTimeAuthorizationStatus(rawValue: status.rawValue), status)
        }
    }

    func testUnavailableAuthorizerReportsFrameworkError() async {
        let authorizer = UnavailableScreenTimeAuthorizer()
        let outcome = await authorizer.requestAuthorization()
        XCTAssertEqual(outcome.status, .unavailable)
        XCTAssertEqual(outcome.error, .frameworkUnavailable)
        XCTAssertFalse(authorizer.isEntitlementAvailable)
    }

    // MARK: - firstOpenWindow (drives the initial shield decision)

    func testFirstOpenWindowReturnsNilWhenNoWindowOpen() {
        var policy = ScreenTimePolicy()
        policy.rules = [.init(kind: .window, name: "Night", startMinutes: 22 * 60, endMinutes: 7 * 60)]
        // 12:00 is outside 22:00→07:00, so the engine must not shield on enable.
        XCTAssertNil(policy.firstOpenWindow(at: date(2026, 3, 13, 12, 0), calendar: calendar))
        XCTAssertFalse(policy.isBlockedByWindow(date(2026, 3, 13, 12, 0), calendar: calendar))
    }

    func testFirstOpenWindowReturnsRuleWhenInsideWindow() {
        var policy = ScreenTimePolicy()
        let rule = ScreenTimePolicy.Rule(kind: .window, name: "Night", startMinutes: 22 * 60, endMinutes: 7 * 60)
        policy.rules = [rule]
        XCTAssertEqual(policy.firstOpenWindow(at: date(2026, 3, 13, 23, 30), calendar: calendar)?.id, rule.id)
        // Early-morning tail of a midnight-crossing window.
        XCTAssertEqual(policy.firstOpenWindow(at: date(2026, 3, 14, 2, 0), calendar: calendar)?.id, rule.id)
    }

    func testFirstOpenWindowIgnoresDisabledRule() {
        var policy = ScreenTimePolicy()
        policy.rules = [.init(kind: .window, name: "Night", startMinutes: 22 * 60, endMinutes: 7 * 60, isEnabled: false)]
        XCTAssertNil(policy.firstOpenWindow(at: date(2026, 3, 13, 23, 0), calendar: calendar))
    }
}
