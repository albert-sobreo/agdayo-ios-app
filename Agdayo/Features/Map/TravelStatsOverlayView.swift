import SwiftUI

/// A Strava-style sticker: genuinely transparent background (no
/// `.background()` anywhere in this view), so it drops cleanly onto any
/// photo in whatever app the user picks from the share sheet — Instagram
/// Stories, Photos markup, WhatsApp, etc. all accept transparent-PNG
/// stickers natively, so no in-app photo compositor is needed.
struct TravelStatsOverlayView: View {
    let countries: Int
    let cities: Int
    let trips: Int
    let days: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 32)
                .padding(.bottom, 96)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("MY TRAVELS")
                    .font(AppFont.outfit(13, weight: .bold, relativeTo: .caption))
                    .tracking(2)
                HStack(spacing: 28) {
                    StatColumn(value: countries, label: countries > 1 ? "Countries" : "Country")
                    StatColumn(value: cities, label: cities > 1 ? "Cities": "City")
                }
                HStack(spacing: 28) {
                    StatColumn(value: trips, label: trips > 1 ? "Trips" : "Trip")
                    StatColumn(value: days, label: days > 1 ? "Days" : "Day")
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 6)
            .padding(.top, 48)
        }
    }
}

private struct StatColumn: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(AppFont.outfit(34, weight: .bold, relativeTo: .largeTitle))
            Text(label.uppercased())
                .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                .tracking(1)
                .opacity(0.85)
        }
        .frame(width: 100, alignment: .leading)
    }
}

/// Deduped country/city counts + totals across completed trips only —
/// mirrors `VisitedPlacesMapView`'s own "visited" definition.
enum TravelStats {
    static func compute(from trips: [Trip]) -> TravelStatsOverlayView {
        let completed = trips.filter { $0.status == .completed }
        let countries = Set(completed.compactMap(\.visitedCountry)).count
        let cities = Set(completed.compactMap(\.visitedCity)).count
        let totalDays = completed.reduce(0) { $0 + $1.numberOfDays }
        return TravelStatsOverlayView(countries: countries, cities: cities, trips: completed.count, days: totalDays)
    }
}
