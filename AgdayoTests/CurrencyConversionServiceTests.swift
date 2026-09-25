import Testing
@testable import Agdayo

/// Only the `from == to` short-circuit — the network branch is out of scope
/// for a unit test (no injected `URLSession`, would hit the live API).
struct CurrencyConversionServiceTests {
    @Test func fetchRateShortCircuitsToOneForSameCurrency() async {
        let rate = await CurrencyConversionService.fetchRate(from: "PHP", to: "PHP")
        #expect(rate == 1)
    }
}
