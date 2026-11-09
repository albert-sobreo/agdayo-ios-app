import Foundation
import Testing
@testable import Agdayo

struct ItineraryOrderTests {
    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: .now))!
    }

    private func ordered(_ items: [(String, ItineraryOrder.Key)]) -> [String] {
        items.sorted { ItineraryOrder.precedes($0.1, $1.1) }.map(\.0)
    }

    @Test func activityAtDepartureTimeComesBeforeTheDeparture() {
        let names = ordered([
            ("depart", .init(time: at(10), rank: .departure)),
            ("activity", .init(time: at(10), rank: .other)),
        ])
        #expect(names == ["activity", "depart"])
    }

    @Test func activityAtArrivalTimeComesAfterTheArrival() {
        let names = ordered([
            ("activity", .init(time: at(12), rank: .other)),
            ("arrive", .init(time: at(12), rank: .arrival)),
            ("depart", .init(time: at(10), rank: .departure)),
        ])
        #expect(names == ["depart", "arrive", "activity"])
    }

    @Test func activityBetweenDepartureAndArrivalSitsBetweenThem() {
        let names = ordered([
            ("arrive", .init(time: at(12), rank: .arrival)),
            ("depart", .init(time: at(10), rank: .departure)),
            ("activity", .init(time: at(11), rank: .other)),
        ])
        #expect(names == ["depart", "activity", "arrive"])
    }

    @Test func legThatArrivesTheMinuteItLeavesKeepsDepartureFirst() {
        let names = ordered([
            ("arrive", .init(time: at(10), rank: .instantArrival)),
            ("activity", .init(time: at(10), rank: .other)),
            ("depart", .init(time: at(10), rank: .departure)),
        ])
        #expect(names == ["activity", "depart", "arrive"])
    }

    @Test func secondsDoNotOutweighTheSameMinuteRule() {
        let names = ordered([
            ("activity", .init(time: at(12).addingTimeInterval(-20), rank: .other)),
            ("arrive", .init(time: at(12).addingTimeInterval(-30), rank: .arrival)),
        ])
        #expect(names == ["arrive", "activity"])
    }
}
