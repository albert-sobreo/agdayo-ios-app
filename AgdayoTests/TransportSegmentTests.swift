import Foundation
import Testing
@testable import Agdayo

struct TransportSegmentTests {
    @Test func costAndRateSameCurrencyReturnsRateOfOne() {
        let segment = TransportSegment(cost: 100, currency: "PHP")
        let result = segment.costAndRate(inTripCurrency: "PHP")
        #expect(result?.cost == 100)
        #expect(result?.rate == 1)
    }

    @Test func costAndRateConvertsUsingCapturedExchangeRate() {
        let segment = TransportSegment(cost: 10, currency: "USD", exchangeRateToTripCurrency: 56)
        let result = segment.costAndRate(inTripCurrency: "PHP")
        #expect(result?.cost == 560)
        #expect(result?.rate == 56)
    }

    @Test func costAndRateReturnsNilWhenForeignCurrencyHasNoCapturedRate() {
        let segment = TransportSegment(cost: 10, currency: "USD")
        #expect(segment.costAndRate(inTripCurrency: "PHP") == nil)
    }

    @Test func departureDateTimeCombinesDateAndParsedTime() {
        let day = Calendar.current.startOfDay(for: .now)
        let segment = TransportSegment(departureDate: day, departureTime: "14:30")
        let expected = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: day)!
        #expect(segment.departureDateTime == expected)
    }

    @Test func departureDateTimeFallsBackToDateOnMalformedTime() {
        let day = Calendar.current.startOfDay(for: .now)
        let segment = TransportSegment(departureDate: day, departureTime: "not-a-time")
        #expect(segment.departureDateTime == day)
    }

    @Test func arrivalDateTimeNilWhenNoArrivalDetails() {
        let segment = TransportSegment()
        #expect(segment.arrivalDateTime == nil)
    }

    @Test func arrivalDateTimeCombinesArrivalDateAndTime() {
        let day = Calendar.current.startOfDay(for: .now)
        let segment = TransportSegment(arrivalDate: day, arrivalTime: "09:15")
        let expected = Calendar.current.date(bySettingHour: 9, minute: 15, second: 0, of: day)!
        #expect(segment.arrivalDateTime == expected)
    }
}
