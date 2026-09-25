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
}
