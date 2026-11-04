import Foundation
import Testing
@testable import Agdayo

@MainActor
struct AppLinkTests {
    private var manila: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Manila")!
        return calendar
    }

    @Test func joinLinkKeepsTheCode() {
        #expect(AppLink(url: URL(string: "agdayo://join?code=ABC123")!) == .join(code: "ABC123"))
        #expect(AppLink(url: URL(string: "agdayo://join")!) == .join(code: nil))
    }

    @Test func tripLinkWithDay() throws {
        let url = try #require(URL(string: "agdayo://trip/55D69F87-4A05-41F5-AC8D-A7968371C17F?day=2026-11-17"))
        let expectedDay = try #require(manila.date(from: DateComponents(year: 2026, month: 11, day: 17)))
        #expect(AppLink(url: url, calendar: manila) == .trip(id: UUID(uuidString: "55D69F87-4A05-41F5-AC8D-A7968371C17F")!, day: expectedDay))
    }

    @Test func tripLinkWithoutOrWithBadDay() throws {
        let id = try #require(UUID(uuidString: "55D69F87-4A05-41F5-AC8D-A7968371C17F"))
        #expect(AppLink(url: URL(string: "agdayo://trip/55d69f87-4a05-41f5-ac8d-a7968371c17f")!) == .trip(id: id, day: nil))
        #expect(AppLink(url: URL(string: "agdayo://trip/\(id.uuidString)?day=2026-02-30")!, calendar: manila) == .trip(id: id, day: nil))
    }

    @Test func rejectsOtherLinks() {
        #expect(AppLink(url: URL(string: "agdayo://trip/not-a-trip")!) == nil)
        #expect(AppLink(url: URL(string: "agdayo://somewhere")!) == nil)
        #expect(AppLink(url: URL(string: "https://agdayo.example/open/trip/x")!) == nil)
    }
}
