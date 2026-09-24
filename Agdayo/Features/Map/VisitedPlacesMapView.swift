import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

private enum PlaceGrouping: String, CaseIterable, Identifiable {
    case country = "Country"
    case province = "Province"
    case city = "City"

    var id: String { rawValue }
}

private struct VisitedPlace: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let tripCount: Int
}

/// "Places I've actually been" — grouped from completed trips only (not
/// upcoming/planned ones), by country/province/city. `Trip.location` is a
/// flat string with no structured breakdown, so `visitedCountry`/
/// `visitedProvince`/`visitedCity` are reverse-geocoded here the same
/// self-healing way `GlobalMapView.geocodeMissingTrips()` backfills
/// coordinates, just via `CLGeocoder.reverseGeocodeLocation` instead of
/// forward-geocoding.
struct VisitedPlacesMapView: View {
    @Query(sort: \Trip.startDate) private var trips: [Trip]

    @State private var grouping: PlaceGrouping = .country
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var isGeneratingSnapshot = false
    @State private var shareItem: ShareItem?

    private var completedTrips: [Trip] {
        trips.filter { $0.status == .completed }
    }

    private var groupedPlaces: [VisitedPlace] {
        var buckets: [String: [Trip]] = [:]
        for trip in completedTrips {
            guard trip.coordinate != nil, let key = groupKey(for: trip) else { continue }
            buckets[key, default: []].append(trip)
        }
        return buckets.compactMap { key, trips in
            guard let coordinate = trips.first?.coordinate else { return nil }
            return VisitedPlace(id: key, coordinate: coordinate, tripCount: trips.count)
        }
        .sorted { $0.id < $1.id }
    }

    private func groupKey(for trip: Trip) -> String? {
        switch grouping {
        case .country: return trip.visitedCountry
        case .province: return trip.visitedProvince
        case .city: return trip.visitedCity
        }
    }

    var body: some View {
        Group {
            if groupedPlaces.isEmpty {
                EmptyStateView(
                    iconName: "globe",
                    title: "No Visited Places Yet",
                    message: "Places from your completed trips will show up here."
                )
            } else {
                Map(position: $cameraPosition) {
                    ForEach(groupedPlaces) { place in
                        Annotation(place.id, coordinate: place.coordinate, anchor: .bottom) {
                            PlacePinView(name: place.id, tripCount: place.tripCount)
                        }
                    }
                }
                .onAppear(perform: fitAllPlaces)
                .onChange(of: grouping) { _, _ in fitAllPlaces() }
                .onMapCameraChange { context in
                    visibleRegion = context.region
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        shareStats()
                    } label: {
                        Label("Share My Stats", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.appPrimary)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .navigationTitle("Travel Map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Group by", selection: $grouping) {
                    ForEach(PlaceGrouping.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                ShareMapButton(isGenerating: isGeneratingSnapshot, action: shareSnapshot)
                    .disabled(groupedPlaces.isEmpty)
            }
        }
        .task {
            await geocodeMissingVisitedPlaces()
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
    }

    private func fitAllPlaces() {
        let coordinates = groupedPlaces.map(\.coordinate)
        guard !coordinates.isEmpty else { return }
        let rect = coordinates.reduce(MKMapRect.null) { partial, coordinate in
            let point = MKMapPoint(coordinate)
            return partial.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        cameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.2 - 500, dy: -rect.height * 0.2 - 500))
    }

    /// Runs once per launch per trip that hasn't been reverse-geocoded yet —
    /// `visitedCountry == nil` is the "never attempted" signal, since a
    /// successful reverse-geocode almost always resolves a country even when
    /// province/city come back empty for a very rural coordinate.
    private func geocodeMissingVisitedPlaces() async {
        let geocoder = CLGeocoder()
        for trip in completedTrips where trip.visitedCountry == nil {
            guard let coordinate = trip.coordinate else { continue }
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else { continue }

            trip.visitedCountry = placemark.country
            trip.visitedProvince = placemark.administrativeArea
            trip.visitedCity = placemark.locality

            guard trip.ownerUID != nil else { continue }
            let tripID = trip.id
            let name = trip.name
            let location2 = trip.location
            let theme = trip.theme.rawValue
            let startDate = trip.startDate
            let endDate = trip.endDate
            let overallBudget = trip.overallBudget
            let currency = trip.currency
            let tripDescription = trip.tripDescription
            let latitude = trip.latitude
            let longitude = trip.longitude
            let visitedCountry = trip.visitedCountry
            let visitedProvince = trip.visitedProvince
            let visitedCity = trip.visitedCity
            Task {
                try? await TripMembershipService.updateTripRecord(
                    tripID: tripID, name: name, location: location2, theme: theme,
                    startDate: startDate, endDate: endDate, overallBudget: overallBudget,
                    currency: currency, tripDescription: tripDescription,
                    latitude: latitude, longitude: longitude,
                    visitedCountry: visitedCountry, visitedProvince: visitedProvince, visitedCity: visitedCity
                )
            }
        }
    }

    private var fallbackRegion: MKCoordinateRegion {
        let coordinates = groupedPlaces.map(\.coordinate)
        let rect = coordinates.reduce(MKMapRect.null) { partial, coordinate in
            let point = MKMapPoint(coordinate)
            return partial.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        return MKCoordinateRegion(rect.insetBy(dx: -rect.width * 0.2 - 500, dy: -rect.height * 0.2 - 500))
    }

    /// `isOpaque = false` + `.pngData()` (not `.jpegData()`) keeps the alpha
    /// channel, so the exported image is a genuine sticker — no background
    /// rectangle — that overlays cleanly onto any photo.
    private func shareStats() {
        let renderer = ImageRenderer(content: TravelStats.compute(from: trips))
        renderer.isOpaque = false
        renderer.scale = 3
        guard let uiImage = renderer.uiImage, let data = uiImage.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agdayo-travel-stats-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            shareItem = ShareItem(url: url)
        } catch {
            // Sharing just won't happen this time; nothing destructive to recover from.
        }
    }

    private func shareSnapshot() {
        guard !groupedPlaces.isEmpty else { return }
        isGeneratingSnapshot = true

        let options = MKMapSnapshotter.Options()
        options.region = visibleRegion ?? fallbackRegion
        options.size = CGSize(width: 1080, height: 1080)

        let places = groupedPlaces
        MKMapSnapshotter(options: options).start { snapshot, _ in
            isGeneratingSnapshot = false
            guard let snapshot,
                  let data = composeShareImage(snapshot: snapshot, places: places).pngData() else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("agdayo-travel-map-\(UUID().uuidString).png")
            do {
                try data.write(to: url)
                shareItem = ShareItem(url: url)
            } catch {
                // Sharing just won't happen this time; nothing destructive to recover from.
            }
        }
    }

    /// `MKMapSnapshotter` never includes annotations — mirrors
    /// `GlobalMapView.drawPin` but labels a grouped place (with its trip
    /// count) instead of a single trip.
    private func composeShareImage(snapshot: MKMapSnapshotter.Snapshot, places: [VisitedPlace]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            for place in places {
                drawPin(for: place, at: snapshot.point(for: place.coordinate))
            }
        }
    }

    private func drawPin(for place: VisitedPlace, at tip: CGPoint) {
        let label = place.tripCount > 1 ? "\(place.id) (\(place.tripCount))" : place.id
        let font = UIFont(name: "Outfit-Bold", size: 15) ?? .boldSystemFont(ofSize: 15)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let textSize = label.size(withAttributes: attributes)

        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 8
        let tailHeight: CGFloat = 8
        let pillSize = CGSize(width: textSize.width + horizontalPadding * 2, height: textSize.height + verticalPadding * 2)
        let pillRect = CGRect(
            x: tip.x - pillSize.width / 2, y: tip.y - pillSize.height - tailHeight,
            width: pillSize.width, height: pillSize.height
        )
        let color = UIColor(Color.appPrimary)

        let tail = UIBezierPath()
        tail.move(to: tip)
        tail.addLine(to: CGPoint(x: tip.x - 7, y: pillRect.maxY))
        tail.addLine(to: CGPoint(x: tip.x + 7, y: pillRect.maxY))
        tail.close()
        color.setFill()
        tail.fill()

        let pill = UIBezierPath(roundedRect: pillRect, cornerRadius: pillRect.height / 2)
        color.setFill()
        pill.fill()
        UIColor.white.withAlphaComponent(0.85).setStroke()
        pill.lineWidth = 2
        pill.stroke()

        let textRect = CGRect(
            x: pillRect.midX - textSize.width / 2, y: pillRect.midY - textSize.height / 2,
            width: textSize.width, height: textSize.height
        )
        label.draw(in: textRect, withAttributes: attributes)
    }
}

private struct PlacePinView: View {
    let name: String
    let tripCount: Int

    var body: some View {
        VStack(spacing: -2) {
            label
                .fixedSize()
            PinTail()
                .fill(Color.appPrimary)
                .frame(width: 14, height: 8)
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }

    @ViewBuilder
    private var label: some View {
        let text = tripCount > 1 ? "\(name) (\(tripCount))" : name
        let styledText = Text(text)
            .font(AppFont.outfit(13, weight: .bold, relativeTo: .caption))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

        if #available(iOS 26, *) {
            styledText.glassEffect(.regular.tint(.appPrimary).interactive(), in: Capsule())
        } else {
            styledText.background(Color.appPrimary, in: Capsule())
        }
    }
}

private struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareMapButton: View {
    let isGenerating: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if isGenerating {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .accessibilityLabel("Share Map")
    }
}
