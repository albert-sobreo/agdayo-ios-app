import CoreLocation
import WeatherKit

struct DailyForecastSummary {
    let date: Date
    let symbolName: String
    let highTemperature: Measurement<UnitTemperature>
    let lowTemperature: Measurement<UnitTemperature>
}

/// Thin WeatherKit wrapper for the itinerary's per-day forecast chips — a
/// derived display value, never stored or synced. Requires the WeatherKit
/// capability to be enabled for this App ID in the Apple Developer portal;
/// until then (or without network), calls throw and callers should just
/// show nothing rather than an error.
enum WeatherForecastService {
    static func dailyForecast(for coordinate: CLLocationCoordinate2D) async throws -> [DailyForecastSummary] {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let weather = try await WeatherService.shared.weather(for: location)
        return weather.dailyForecast.map {
            DailyForecastSummary(
                date: $0.date,
                symbolName: $0.symbolName,
                highTemperature: $0.highTemperature,
                lowTemperature: $0.lowTemperature
            )
        }
    }
}
