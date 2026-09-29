import Foundation

/// Astronomical prayer-time calculation.
///
/// Direct port of `com.analoganchor.app.data.PrayerTimesCalculator` (Android).
/// Preserves the exact same math (Keplerian solar elements, hour-angle
/// computation) and the same altitude conventions so results match the
/// Android baseline:
///   - Fajr  : -18.0°
///   - Sunrise / Maghrib : -0.833°
///   - Isha  : -17.0°
///   - Asr   : Shafi/Maliki/Hanbali (shadow length = object + midday shadow)
public struct PrayerTimesCalculator {

    public let latitude: Double
    public let longitude: Double
    public let timezoneOffset: Double

    public init(latitude: Double, longitude: Double, timezoneOffset: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.timezoneOffset = timezoneOffset
    }

    // MARK: - Public result

    public struct PrayerTimes: Equatable, Sendable {
        public let fajr: Date
        public let sunrise: Date
        public let dhuhr: Date
        public let asr: Date
        public let maghrib: Date
        public let isha: Date

        public init(fajr: Date, sunrise: Date, dhuhr: Date, asr: Date, maghrib: Date, isha: Date) {
            self.fajr = fajr
            self.sunrise = sunrise
            self.dhuhr = dhuhr
            self.asr = asr
            self.maghrib = maghrib
            self.isha = isha
        }

        /// Ordered (name, date) pairs, matching the Android dashboard order.
        public var ordered: [(name: String, time: Date)] {
            [("Fajr", fajr), ("Sunrise", sunrise), ("Dhuhr", dhuhr),
             ("Asr", asr), ("Maghrib", maghrib), ("Isha", isha)]
        }
    }

    // MARK: - Calculation

    /// Calculates prayer times for the given calendar day.
    /// - Note: `calendar` supplies the year/month/day; the returned dates keep the
    ///   same calendar/time zone as the input day at the computed wall-clock time.
    public func calculateTimes(for date: Date, calendar: Calendar = .current) -> PrayerTimes {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 2000
        let month = comps.month ?? 1
        let day = comps.day ?? 1

        let jd = julianDate(year: year, month: month, day: day)
        let d = jd - 2_451_545.0

        // Keplerian elements of the Sun.
        let g = 357.529 + 0.98560028 * d
        let q = 280.459 + 0.98564736 * d
        let l = q + 1.915 * sin(deg2rad(g)) + 0.02 * sin(deg2rad(2.0 * g))
        let e = 23.439 - 0.00000036 * d

        let dec = rad2deg(asin(sin(deg2rad(e)) * sin(deg2rad(l))))

        var ra = rad2deg(atan2(cos(deg2rad(e)) * sin(deg2rad(l)), cos(deg2rad(l))))
        ra = (ra + 360.0).truncatingRemainder(dividingBy: 360.0)

        // Adjust RA quadrant.
        let lQuad = floor(l / 90.0) * 90.0
        let raQuad = floor(ra / 90.0) * 90.0
        let raAdj = ra + (lQuad - raQuad)

        // Equation of time (hours).
        let eqt = ((q + 360.0).truncatingRemainder(dividingBy: 360.0) - raAdj) / 15.0

        // Midday / Dhuhr.
        let midday = 12.0 - (longitude / 15.0) - eqt + timezoneOffset

        func hourAngle(_ altitude: Double) -> Double {
            let num = sin(deg2rad(altitude)) - sin(deg2rad(latitude)) * sin(deg2rad(dec))
            let den = cos(deg2rad(latitude)) * cos(deg2rad(dec))
            let cosH = num / den
            if cosH > 1.0 || cosH < -1.0 { return .nan }
            return rad2deg(acos(cosH)) / 15.0
        }

        // Sunrise & Sunset (Maghrib).
        let hSunrise = hourAngle(-0.833)
        let sunriseHour = hSunrise.isNaN ? midday - 6.0 : midday - hSunrise
        let maghribHour = hSunrise.isNaN ? midday + 6.0 : midday + hSunrise

        // Fajr.
        let hFajr = hourAngle(-18.0)
        let fajrHour = hFajr.isNaN ? midday - 7.2 : midday - hFajr

        // Isha.
        let hIsha = hourAngle(-17.0)
        let ishaHour = hIsha.isNaN ? midday + 7.2 : midday + hIsha

        // Asr (Shafi/Maliki/Hanbali).
        let altAsr = rad2deg(atan(1.0 / (1.0 + tan(deg2rad(abs(latitude - dec))))))
        let hAsr = hourAngle(altAsr)
        let asrHour = hAsr.isNaN ? midday + 3.0 : midday + hAsr

        func toDate(_ hourValue: Double) -> Date {
            var h = hourValue
            while h < 0.0 { h += 24.0 }
            while h >= 24.0 { h -= 24.0 }

            let hour = Int(h)
            let minuteVal = (h - Double(hour)) * 60.0
            let minute = Int(minuteVal)
            let second = Int((minuteVal - Double(minute)) * 60.0)

            var comps = calendar.dateComponents([.year, .month, .day], from: date)
            comps.hour = hour
            comps.minute = minute
            comps.second = second
            comps.nanosecond = 0
            return calendar.date(from: comps) ?? date
        }

        return PrayerTimes(
            fajr: toDate(fajrHour),
            sunrise: toDate(sunriseHour),
            dhuhr: toDate(midday),
            asr: toDate(asrHour),
            maghrib: toDate(maghribHour),
            isha: toDate(ishaHour)
        )
    }

    // MARK: - Julian date

    private func julianDate(year: Int, month: Int, day: Int) -> Double {
        var y = year
        var m = month
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = Int(Double(y) / 100.0)
        let b = Int(Double(a) / 4.0)
        let c = 2 - a + b
        let e = Int(365.25 * Double(y + 4716))
        let f = Int(30.6001 * Double(m + 1))
        return Double(c + day + e + f) - 1_524.5
    }

    // MARK: - Trig helpers (degrees)

    @inline(__always) private func deg2rad(_ degrees: Double) -> Double {
        degrees * .pi / 180.0
    }

    @inline(__always) private func rad2deg(_ radians: Double) -> Double {
        radians * 180.0 / .pi
    }
}
