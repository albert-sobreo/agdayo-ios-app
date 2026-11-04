import Foundation
import Testing
@testable import Agdayo

struct ArrivalDepartureTests {
    private let calendar = Calendar.current

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let start = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start)!
    }

    /// Nights from `start` to `end`, check-in 15:00, check-out 11:00.
    private func stay(_ name: String, from start: Int, to end: Int) -> Accommodation {
        Accommodation(name: name, latitude: 1.3, longitude: 103.8, startDate: at(start, 0), endDate: at(end, 0))
    }

    @Test func readyTimeAfterArriving() {
        #expect(TravelPlanning.readyAfterArrival(mode: .flight, arrival: at(1, 12)) == at(1, 12, 45))
        #expect(TravelPlanning.readyAfterArrival(mode: .bus, arrival: at(1, 12)) == at(1, 12, 15))
    }

    @Test func beThereByDependsOnMode() {
        #expect(TravelPlanning.beThereBy(mode: .flight, departure: at(3, 10)) == at(3, 8))
        #expect(TravelPlanning.beThereBy(mode: .train, departure: at(3, 10)) == at(3, 9, 40))
        #expect(TravelPlanning.beThereBy(mode: .rideshare, departure: at(3, 10)) == nil)
    }

    @Test func arrivingGoesToThatNightsStay() {
        let hotel = stay("Hotel", from: 1, to: 3)
        #expect(TravelPlanning.stay(afterArrivingAt: at(1, 12), in: [hotel])?.name == "Hotel")
        // Landing after check-out on the last day: nowhere to go.
        #expect(TravelPlanning.stay(afterArrivingAt: at(3, 18), in: [hotel]) == nil)
    }

    @Test func departingLeavesFromTheStayYouCheckedInto() {
        let hotel = stay("Hotel", from: 1, to: 3)
        #expect(TravelPlanning.stay(beforeDepartingAt: at(3, 10), in: [hotel])?.name == "Hotel")
        // The outbound flight on day 1 leaves before check-in, so not from this hotel.
        #expect(TravelPlanning.stay(beforeDepartingAt: at(1, 8), in: [hotel]) == nil)
    }

    @Test func movingBetweenCitiesPicksTheRightStay() {
        let first = stay("First", from: 1, to: 3)
        let second = stay("Second", from: 3, to: 5)
        #expect(TravelPlanning.stay(beforeDepartingAt: at(3, 10), in: [first, second])?.name == "First")
        #expect(TravelPlanning.stay(afterArrivingAt: at(3, 14), in: [first, second])?.name == "Second")
    }
}
