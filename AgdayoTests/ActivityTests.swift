import Foundation
import Testing
@testable import Agdayo

struct ActivityTests {
    @Test func costAndRateSameCurrencyReturnsRateOfOne() {
        let activity = Activity(title: "Museum", cost: 100, costCurrency: "PHP")
        let result = activity.costAndRate(inTripCurrency: "PHP")
        #expect(result?.cost == 100)
        #expect(result?.rate == 1)
    }

    @Test func costAndRateNilCostCurrencyMatchesTripCurrency() {
        let activity = Activity(title: "Museum", cost: 100)
        let result = activity.costAndRate(inTripCurrency: "PHP")
        #expect(result?.cost == 100)
        #expect(result?.rate == 1)
    }

    @Test func costAndRateConvertsUsingCapturedExchangeRate() {
        let activity = Activity(title: "Museum", cost: 10, costCurrency: "USD", exchangeRateToTripCurrency: 56)
        let result = activity.costAndRate(inTripCurrency: "PHP")
        #expect(result?.cost == 560)
        #expect(result?.rate == 56)
    }

    @Test func costAndRateReturnsNilWhenForeignCurrencyHasNoCapturedRate() {
        let activity = Activity(title: "Museum", cost: 10, costCurrency: "USD")
        #expect(activity.costAndRate(inTripCurrency: "PHP") == nil)
    }

    @Test func costAndRateReturnsNilWhenNoCost() {
        let activity = Activity(title: "Free tour")
        #expect(activity.costAndRate(inTripCurrency: "PHP") == nil)
    }

    @Test func coordinateRequiresBothLatitudeAndLongitude() {
        let activity = Activity(title: "Museum", latitude: 14.5)
        #expect(activity.coordinate == nil)
        activity.longitude = 121.0
        #expect(activity.coordinate != nil)
    }

    @Test func laterSameDayKeepsOnlyLaterActivitiesOnThatDayInOrder() {
        let calendar = Calendar.current
        let day = calendar.date(from: DateComponents(year: 2026, month: 12, day: 10, hour: 0))!
        func at(_ hour: Int, dayOffset: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(day: dayOffset, hour: hour), to: day)!
        }
        let moved = Activity(title: "Lunch", date: at(12))
        let breakfast = Activity(title: "Breakfast", date: at(8))
        let together = Activity(title: "Same time", date: at(12))
        let dinner = Activity(title: "Dinner", date: at(19))
        let museum = Activity(title: "Museum", date: at(14))
        let tomorrow = Activity(title: "Tomorrow", date: at(9, dayOffset: 1))

        let later = ActivitySaver.laterSameDay(
            after: moved.date,
            in: [moved, breakfast, together, dinner, museum, tomorrow],
            excluding: moved.id
        )
        #expect(later.map(\.title) == ["Museum", "Dinner"])
    }

    @Test func unknownTransportModeDecodesAsOther() throws {
        let modes = try JSONDecoder().decode([TransportMode].self, from: Data(#"["jeepney","hoverboard"]"#.utf8))
        #expect(modes == [.jeepney, .other])
    }
}
