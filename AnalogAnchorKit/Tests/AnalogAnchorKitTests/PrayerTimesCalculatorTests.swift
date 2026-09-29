import XCTest
@testable import AnalogAnchorKit

final class PrayerTimesCalculatorTests: XCTestCase {

    func testReturnsSixOrderedTimesForKnownDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bahrain")!
        let calc = PrayerTimesCalculator(latitude: 26.2285, longitude: 50.5860, timezoneOffset: 3.0)

        let day = calendar.date(from: DateComponents(year: 2026, month: 5, day: 15))!
        let times = calc.calculateTimes(for: day, calendar: calendar)

        // Bahrain in May: Fajr before Sunrise before Dhuhr before Asr before Maghrib before Isha.
        XCTAssertLessThan(times.fajr, times.sunrise)
        XCTAssertLessThan(times.sunrise, times.dhuhr)
        XCTAssertLessThan(times.dhuhr, times.asr)
        XCTAssertLessThan(times.asr, times.maghrib)
        XCTAssertLessThan(times.maghrib, times.isha)
        XCTAssertEqual(times.ordered.count, 6)
    }

    func testFajrIsBeforeSunriseYearRound() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Bahrain")!
        let calc = PrayerTimesCalculator(latitude: 26.2285, longitude: 50.5860, timezoneOffset: 3.0)

        for month in 1...12 {
            let day = calendar.date(from: DateComponents(year: 2026, month: month, day: 15))!
            let times = calc.calculateTimes(for: day, calendar: calendar)
            XCTAssertLessThan(times.fajr, times.sunrise, "Fajr should precede sunrise in month \(month)")
        }
    }

    func testHighLatitudeDoesNotCrash() {
        // Tromsø, Norway — polar day in June can make some hour angles undefined.
        let calc = PrayerTimesCalculator(latitude: 69.65, longitude: 18.96, timezoneOffset: 1.0)
        let times = calc.calculateTimes(for: Date())
        XCTAssertNotNil(times.fajr)
        XCTAssertNotNil(times.isha)
    }
}
