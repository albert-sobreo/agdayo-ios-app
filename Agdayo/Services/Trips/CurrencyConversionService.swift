import Foundation

/// Live exchange rates for converting a cost entered in a different currency
/// than the trip's own, via a free, no-API-key endpoint — no backend of our
/// own involved. Callers snapshot the returned rate onto the item at entry
/// time (see `Activity`/`TransportSegment.exchangeRateToTripCurrency`)
/// rather than re-fetching it live later, so a trip's totals don't drift if
/// rates change after the fact. Returns `nil` on any failure (offline, rate
/// limited, unknown currency) so the caller can fall back to manual entry.
enum CurrencyConversionService {
    private struct RatesResponse: Decodable {
        let rates: [String: Double]
    }

    /// The multiplier to turn an amount in `from` into `to` (1 `from` = `rate` `to`).
    static func fetchRate(from: String, to: String) async -> Double? {
        guard from != to else { return 1 }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(from)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(RatesResponse.self, from: data)
            return decoded.rates[to]
        } catch {
            return nil
        }
    }
}
