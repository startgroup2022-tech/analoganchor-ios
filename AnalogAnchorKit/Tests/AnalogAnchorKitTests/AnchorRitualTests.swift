import XCTest
@testable import AnalogAnchorKit

/// Tests for `AnchorRitual`, ported from the session logic in `AnchorViewModel.kt`.
final class AnchorRitualTests: XCTestCase {

    // MARK: - Duration availability

    func testDurationAvailabilityMirrorsAndroidCaps() {
        let fresh = AnchorRitual.DailyCounters()
        XCTAssertTrue(fresh.isDurationAvailable(25))
        XCTAssertTrue(fresh.isDurationAvailable(5))

        // One short session used: long durations blocked, second short allowed.
        let oneShort = AnchorRitual.DailyCounters(shortSessionCount: 1)
        XCTAssertFalse(oneShort.isDurationAvailable(25))
        XCTAssertTrue(oneShort.isDurationAvailable(5))

        // Two short sessions: nothing left.
        let twoShort = AnchorRitual.DailyCounters(shortSessionCount: 2)
        XCTAssertFalse(twoShort.isDurationAvailable(5))
        XCTAssertFalse(twoShort.isDurationAvailable(25))

        // A long session used: the day is exhausted.
        let longUsed = AnchorRitual.DailyCounters(hasLongSessionToday: true)
        XCTAssertFalse(longUsed.isDurationAvailable(5))
        XCTAssertFalse(longUsed.isDurationAvailable(25))
    }

    func testStartRejectsUnavailableDuration() {
        let counters = AnchorRitual.DailyCounters(hasLongSessionToday: true)
        XCTAssertThrowsError(try AnchorRitual.start(durationMinutes: 25, counters: counters)) { error in
            XCTAssertEqual(error as? AnchorRitual.RitualError, .durationUnavailable(25))
        }
    }

    // MARK: - Rewards

    func testEarnedPointsMatchAndroidTable() {
        XCTAssertEqual(AnchorRitual.earnedPoints(forDurationMinutes: 5), 25)
        XCTAssertEqual(AnchorRitual.earnedPoints(forDurationMinutes: 10), 35)
        XCTAssertEqual(AnchorRitual.earnedPoints(forDurationMinutes: 15), 45)
        XCTAssertEqual(AnchorRitual.earnedPoints(forDurationMinutes: 25), 25)
    }

    // MARK: - Lifecycle

    func testStartInitialisesCountdownAndResetsDiscipline() throws {
        let now = Date()
        var state = try AnchorRitual.start(durationMinutes: 25, counters: .init(), now: now)
        XCTAssertEqual(state.phase, .running)
        XCTAssertEqual(state.remainingSeconds, 25 * 60)
        XCTAssertEqual(state.pickupCount, 0)
        XCTAssertFalse(state.isPhoneFaceDown)
        XCTAssertEqual(state.startedAt, now)
    }

    func testTickClampsAtZero() throws {
        var state = try AnchorRitual.start(durationMinutes: 5, counters: .init())
        AnchorRitual.tick(&state, elapsedSeconds: 100)
        XCTAssertEqual(state.remainingSeconds, 200)
        AnchorRitual.tick(&state, elapsedSeconds: 9999)
        XCTAssertEqual(state.remainingSeconds, 0)
        XCTAssertEqual(state.phase, .running, "ticking does not itself complete the session")
    }

    func testCompletionCreditsPointsAndUpdatesCounters() throws {
        var state = try AnchorRitual.start(durationMinutes: 25, counters: .init())
        let completion = try AnchorRitual.complete(&state, counters: .init())
        XCTAssertEqual(state.phase, .completed)
        XCTAssertEqual(completion.points, 25)
        XCTAssertTrue(completion.hasLongSessionToday, ">5 min counts as a long session")
        XCTAssertTrue(completion.eveningAnchorCompleted)
        XCTAssertEqual(completion.reflectionCount, 1)
    }

    func testTwoShortSessionsReachFullyCapped() throws {
        var first = try AnchorRitual.start(durationMinutes: 5, counters: .init())
        let firstCompletion = try AnchorRitual.complete(&first, counters: .init())
        XCTAssertFalse(firstCompletion.eveningAnchorCompleted)
        XCTAssertEqual(firstCompletion.shortSessionCount, 1)

        let counters = AnchorRitual.DailyCounters(
            shortSessionCount: firstCompletion.shortSessionCount,
            hasLongSessionToday: firstCompletion.hasLongSessionToday,
            reflectionCount: firstCompletion.reflectionCount
        )
        var second = try AnchorRitual.start(durationMinutes: 5, counters: counters)
        let secondCompletion = try AnchorRitual.complete(&second, counters: counters)
        XCTAssertTrue(secondCompletion.eveningAnchorCompleted, "two short sessions cap the day")
        XCTAssertEqual(secondCompletion.shortSessionCount, 2)
        XCTAssertEqual(secondCompletion.reflectionCount, 2)
    }

    func testCompleteFailsWhenNotRunning() {
        var state = AnchorRitual.State()
        XCTAssertThrowsError(try AnchorRitual.complete(&state, counters: .init())) { error in
            XCTAssertEqual(error as? AnchorRitual.RitualError, .notRunning)
        }
    }

    func testCancelDoesNotCreditAndMarksCancelled() throws {
        var state = try AnchorRitual.start(durationMinutes: 25, counters: .init())
        AnchorRitual.cancel(&state)
        XCTAssertEqual(state.phase, .cancelled)
        XCTAssertEqual(state.remainingSeconds, 0)
    }

    // MARK: - Pickups / orientation

    func testPickupsAreDebounced() throws {
        let t0 = Date()
        var state = try AnchorRitual.start(durationMinutes: 25, counters: .init(), now: t0)
        AnchorRitual.recordPickup(&state, at: t0)
        AnchorRitual.recordPickup(&state, at: t0.addingTimeInterval(1.0)) // within debounce
        XCTAssertEqual(state.pickupCount, 1)
        AnchorRitual.recordPickup(&state, at: t0.addingTimeInterval(2.0)) // past debounce
        XCTAssertEqual(state.pickupCount, 2)
    }

    func testPickupsNeverVoidASession() throws {
        let t0 = Date()
        var state = try AnchorRitual.start(durationMinutes: 25, counters: .init(), now: t0)
        for i in 0..<10 {
            AnchorRitual.recordPickup(&state, at: t0.addingTimeInterval(Double(i) * 3))
        }
        XCTAssertEqual(state.pickupCount, 10)
        XCTAssertEqual(state.phase, .running, "motion pickups do not cancel focus")
    }

    func testOrientationLiftAfterFaceDownCountsAPickup() throws {
        let t0 = Date()
        var state = try AnchorRitual.start(durationMinutes: 25, counters: .init(), now: t0)
        AnchorRitual.updateOrientation(&state, isFaceDown: true, at: t0)
        XCTAssertTrue(state.isPhoneFaceDown)
        AnchorRitual.updateOrientation(&state, isFaceDown: false, at: t0.addingTimeInterval(3))
        XCTAssertFalse(state.isPhoneFaceDown)
        XCTAssertEqual(state.pickupCount, 1)
    }
}
