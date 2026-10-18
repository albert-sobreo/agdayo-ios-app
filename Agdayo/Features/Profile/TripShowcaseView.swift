import CoreLocation
import MapKit
import SwiftUI

/// "Trips with Agdayo": a few numbers about the traveling you've done, then a
/// row of poster cards, one for each finished trip.
struct TripShowcaseSection: View {
    let trips: [Trip]

    /// Finished trips, most recent first.
    private var finished: [Trip] {
        trips
            .filter { $0.status == .completed }
            .sorted { $0.endDate > $1.endDate }
    }

    private var totalDays: Int {
        let calendar = Calendar.current
        return finished.reduce(0) { total, trip in
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: trip.startDate),
                to: calendar.startOfDay(for: trip.endDate)
            ).day ?? 0
            return total + days + 1
        }
    }

    private var placeCount: Int {
        Set(finished.map { $0.location.trimmingCharacters(in: .whitespaces).lowercased() }).count
    }

    var body: some View {
        if finished.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 16) {
                statStrip

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(finished) { trip in
                            TripPosterCard(trip: trip)
                        }
                    }
                    // Room for the cards' shadow: a scroll view clips to its
                    // bounds, which was cutting it off at the top and bottom.
                    .padding(.vertical, 22)
                }
                .scrollClipDisabled()
            }
            .padding(.vertical, 8)
        }
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            stat("\(finished.count)", finished.count == 1 ? "Trip" : "Trips")
            divider
            stat("\(placeCount)", placeCount == 1 ? "Place" : "Places")
            divider
            stat("\(totalDays)", totalDays == 1 ? "Day" : "Days")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(BrandPalette.cardSurface, in: RoundedRectangle(cornerRadius: AppRadius.smallerCard))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 36)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppFont.barlowCondensed(38, weight: .semibold))
                .foregroundStyle(BrandPalette.maroon)
            Text(label)
                .trackedLabel(11)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "airplane.departure")
                .font(.system(size: 28))
                .foregroundStyle(Color.appPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your trips will be showcased here")
                    .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                Text("Once a trip is over, it gets its own card.")
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandPalette.cardSurface, in: RoundedRectangle(cornerRadius: AppRadius.smallerCard))
        .padding(.vertical, 8)
    }
}

/// A finished trip as a poster: a satellite view of the destination under the
/// trip's color, with the place in big Barlow Condensed and a few facts.
struct TripPosterCard: View {
    let trip: Trip

    private static let size = CGSize(width: 260, height: 340)

    @State private var image: UIImage?

    private var dayCount: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: trip.startDate),
            to: calendar.startOfDay(for: trip.endDate)
        ).day ?? 0
        return days + 1
    }

    private var facts: String {
        var parts = ["\(dayCount) day\(dayCount == 1 ? "" : "s")"]
        let activities = trip.activities.count
        if activities > 0 {
            parts.append("\(activities) activit\(activities == 1 ? "y" : "ies")")
        }
        return parts.joined(separator: " · ")
    }

    private var dates: String {
        let start = trip.startDate.formatted(.dateTime.month(.abbreviated).day())
        let end = trip.endDate.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) – \(end)"
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop

            VStack(alignment: .leading, spacing: 6) {
                Text(dates)
                    .trackedLabel(11, color: .white.opacity(0.85))
                Text(trip.location)
                    .font(AppFont.barlowCondensed(40, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                Text(trip.name)
                    .font(AppFont.outfit(14, weight: .medium, relativeTo: .subheadline))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                Text(facts)
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(18)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: trip.theme.accentColor.opacity(0.25), radius: 10, x: 0, y: 6)
        .accessibilityElement(children: .combine)
        .task(id: trip.id) {
            guard image == nil, let coordinate = trip.coordinate else { return }
            image = await DestinationImagery.image(for: coordinate, size: Self.size)
        }
    }

    private var backdrop: some View {
        ZStack {
            LinearGradient(
                colors: [trip.theme.accentColor, trip.theme.accentColor.mix(with: .black, by: 0.5)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.size.width, height: Self.size.height)
                    .clipped()
                    .transition(.opacity)
            }
            // The trip's color over the top, darker toward the text.
            LinearGradient(
                colors: [trip.theme.accentColor.opacity(image == nil ? 0 : 0.25), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.easeOut(duration: 0.4), value: image)
    }
}

/// A satellite picture of a destination from Apple Maps: free, needs no key
/// and works for any place. Kept in memory so scrolling doesn't re-request it.
@MainActor
enum DestinationImagery {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for coordinate: CLLocationCoordinate2D, size: CGSize) async -> UIImage? {
        let key = "\(coordinate.latitude),\(coordinate.longitude),\(Int(size.width))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 40_000, longitudinalMeters: 40_000)
        options.size = size
        options.preferredConfiguration = MKImageryMapConfiguration()

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        cache.setObject(snapshot.image, forKey: key)
        return snapshot.image
    }
}
