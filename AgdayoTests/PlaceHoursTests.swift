import Foundation
import Testing
@testable import Agdayo

@MainActor
struct PlaceHoursTests {
    /// Tue 9:00–17:30 and Fri 18:00 to Sat 02:00, in UTC+8 (like Baguio).
    private let hours = PlaceHours(
        periods: [
            .init(open: .init(day: 2, hour: 9, minute: 0), close: .init(day: 2, hour: 17, minute: 30)),
            .init(open: .init(day: 5, hour: 18, minute: 0), close: .init(day: 6, hour: 2, minute: 0)),
        ],
        utcOffsetMinutes: 480
    )

    private func local(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    @Test func openDuringAPeriod() {
        // Tue 17 Nov 2026, 10:30 in Baguio.
        #expect(hours.isOpen(at: local("2026-11-17T10:30:00+08:00")) == true)
    }

    @Test func closedOutsideEveryPeriod() {
        // Mon 16 Nov 2026 (BenCab's day off) and Tue after closing.
        #expect(hours.isOpen(at: local("2026-11-16T10:30:00+08:00")) == false)
        #expect(hours.isOpen(at: local("2026-11-17T17:30:00+08:00")) == false)
    }

    @Test func periodRunningPastMidnight() {
        #expect(hours.isOpen(at: local("2026-11-21T01:00:00+08:00")) == true)
        #expect(hours.isOpen(at: local("2026-11-21T03:00:00+08:00")) == false)
    }

    @Test func usesThePlacesTimeZoneNotThePhones() {
        // 01:30 UTC on Tue is 09:30 in UTC+8, so open.
        #expect(hours.isOpen(at: local("2026-11-17T01:30:00Z")) == true)
    }

    @Test func openAroundTheClockAndUnknownHours() {
        let always = PlaceHours(periods: [.init(open: .init(day: 0, hour: 0, minute: 0), close: nil)], utcOffsetMinutes: nil)
        #expect(always.isOpen(at: .now) == true)
        #expect(PlaceHours(periods: [], utcOffsetMinutes: 480).isOpen(at: .now) == nil)
    }

    @Test func decodesTheWorkersShape() throws {
        let json = #"[{"open":{"day":2,"hour":9,"minute":0},"close":{"day":2,"hour":17,"minute":30}},{"open":{"day":0,"hour":0,"minute":0}}]"#
        let periods = try JSONDecoder().decode([PlaceHours.Period].self, from: Data(json.utf8))
        #expect(periods.count == 2)
        #expect(periods[1].close == nil)
    }
}
