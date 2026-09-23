import CoreLocation
import MapKit
import SwiftData
import SwiftUI
import UIKit

/// Map tab root — one pin per *trip* (using its destination), not per
/// activity (that's `TripMapView`, reached from inside a trip's detail).
/// Doubles as a shareable "places I've traveled" overview via the Share
/// button, which composites a themed dot per trip onto a map snapshot.
struct GlobalMapView: View {
    @Query(sort: \Trip.startDate) private var trips: [Trip]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var selectedTripID: UUID?
    @State private var mapStyleOption: MapStyleOption = .standard
    @State private var geocodedCoordinates: [UUID: CLLocationCoordinate2D] = [:]
    @State private var isGeneratingSnapshot = false
    @State private var shareItem: ShareItem?

    private var tripsWithCoordinates: [(trip: Trip, coordinate: CLLocationCoordinate2D)] {
        trips.compactMap { trip in
            if let coordinate = trip.coordinate { return (trip, coordinate) }
            if let coordinate = geocodedCoordinates[trip.id] { return (trip, coordinate) }
            return nil
        }
    }

    var body: some View {
        Group {
            if tripsWithCoordinates.isEmpty {
                EmptyStateView(
                    iconName: "map",
                    title: "No Trips Pinned Yet",
                    message: "Trips with a destination will show up here once you add them."
                )
            } else {
                ZStack(alignment: .bottom) {
                    Map(position: $cameraPosition, selection: $selectedTripID) {
                        ForEach(tripsWithCoordinates, id: \.trip.id) { entry in
                            Annotation(
                                entry.trip.name,
                                coordinate: entry.coordinate,
                                anchor: .bottom
                            ) {
                                TripPinView(
                                    trip: entry.trip,
                                    isSelected: entry.trip.id == selectedTripID
                                )
                            }
                            .tag(entry.trip.id)
                        }
                    }
                    .mapStyle(mapStyleOption.mapStyle)
                    .onAppear(perform: fitAllTrips)
                    .onMapCameraChange { context in
                        visibleRegion = context.region
                    }
                    .overlay(alignment: .topTrailing) {
                        VStack(spacing: 10) {
                            MapStylePickerButton(selection: $mapStyleOption)
                            ShareMapButton(
                                isGenerating: isGeneratingSnapshot,
                                action: shareSnapshot
                            )
                        }
                        .padding()
                    }

                    // Floating trip scroller
                    TripChipScroller(
                        trips: tripsWithCoordinates,
                        selectedTripID: selectedTripID,
                        onFocus: focus
                    )
                    .padding(.bottom, 16)
                }
            }
        }
        .navigationTitle("Map")
        .navigationDestination(for: Trip.self) { trip in
            TripDetailView(trip: trip)
        }
        .task {
            await geocodeMissingTrips()
        }
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(activityItems: [item.url])
        }
    }

    private func fitAllTrips() {
        let coordinates = tripsWithCoordinates.map(\.coordinate)
        guard !coordinates.isEmpty else { return }
        let rect = coordinates.reduce(MKMapRect.null) { partial, coordinate in
            let point = MKMapPoint(coordinate)
            return partial.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        cameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.2 - 500, dy: -rect.height * 0.2 - 500))
    }

    private func focus(_ trip: Trip, coordinate: CLLocationCoordinate2D) {
        selectedTripID = trip.id
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 8000, longitudinalMeters: 8000))
        }
    }

    /// One-time, self-healing backfill for trips saved before `Trip` gained a
    /// stored coordinate. Geocodes `trip.location`, caches the result for
    /// this session, and writes it back (locally + to Firestore if shared)
    /// so this never has to run again for that trip.
    private func geocodeMissingTrips() async {
        let geocoder = CLGeocoder()
        for trip in trips where trip.coordinate == nil && geocodedCoordinates[trip.id] == nil {
            let query = trip.location.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty,
                  let placemark = try? await geocoder.geocodeAddressString(query).first,
                  let coordinate = placemark.location?.coordinate else { continue }

            geocodedCoordinates[trip.id] = coordinate
            trip.latitude = coordinate.latitude
            trip.longitude = coordinate.longitude

            guard trip.ownerUID != nil else { continue }
            let tripID = trip.id
            let name = trip.name
            let location = trip.location
            let theme = trip.theme.rawValue
            let startDate = trip.startDate
            let endDate = trip.endDate
            let overallBudget = trip.overallBudget
            let currency = trip.currency
            let tripDescription = trip.tripDescription
            Task {
                try? await TripMembershipService.updateTripRecord(
                    tripID: tripID, name: name, location: location, theme: theme,
                    startDate: startDate, endDate: endDate, overallBudget: overallBudget,
                    currency: currency, tripDescription: tripDescription,
                    latitude: coordinate.latitude, longitude: coordinate.longitude
                )
            }
        }
    }

    private var fallbackRegion: MKCoordinateRegion {
        let coordinates = tripsWithCoordinates.map(\.coordinate)
        let rect = coordinates.reduce(MKMapRect.null) { partial, coordinate in
            let point = MKMapPoint(coordinate)
            return partial.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        return MKCoordinateRegion(rect.insetBy(dx: -rect.width * 0.2 - 500, dy: -rect.height * 0.2 - 500))
    }

    private func shareSnapshot() {
        guard !tripsWithCoordinates.isEmpty else { return }
        isGeneratingSnapshot = true

        let options = MKMapSnapshotter.Options()
        options.region = visibleRegion ?? fallbackRegion
        options.size = CGSize(width: 1080, height: 1080)
        options.mapType = mapStyleOption.mkMapType

        let entries = tripsWithCoordinates
        MKMapSnapshotter(options: options).start { snapshot, _ in
            isGeneratingSnapshot = false
            guard let snapshot,
                  let data = composeShareImage(snapshot: snapshot, entries: entries).pngData() else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("agdayo-trips-map-\(UUID().uuidString).png")
            do {
                try data.write(to: url)
                shareItem = ShareItem(url: url)
            } catch {
                // Sharing just won't happen this time; nothing destructive to recover from.
            }
        }
    }

    /// `MKMapSnapshotter` never includes annotations — every pin has to be
    /// drawn onto the flat snapshot image manually. Mirrors `TripPinView`'s
    /// look (themed circle + monogram + tail) so the shared image matches
    /// what's actually shown live on the map.
    private func composeShareImage(snapshot: MKMapSnapshotter.Snapshot, entries: [(trip: Trip, coordinate: CLLocationCoordinate2D)]) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            for entry in entries {
                drawPin(for: entry.trip, at: snapshot.point(for: entry.coordinate))
            }
        }
    }

    private func drawPin(for trip: Trip, at tip: CGPoint) {
        let font = UIFont(name: "Outfit-Bold", size: 15) ?? .boldSystemFont(ofSize: 15)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
        let textSize = trip.name.size(withAttributes: attributes)

        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 8
        let tailHeight: CGFloat = 8
        let pillSize = CGSize(width: textSize.width + horizontalPadding * 2, height: textSize.height + verticalPadding * 2)
        let pillRect = CGRect(
            x: tip.x - pillSize.width / 2, y: tip.y - pillSize.height - tailHeight,
            width: pillSize.width, height: pillSize.height
        )
        let color = UIColor(trip.theme.accentColor)

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
        trip.name.draw(in: textRect, withAttributes: attributes)
    }
}

/// A colorful glass "flag" pin — the full trip name in Outfit, on a
/// Liquid Glass pill tinted by the trip's theme (iOS 26+, falling back to a
/// solid pill below that — same pattern as `AppButtonStyle`), with a pointed
/// tail so it still reads as a map pin. Bounces slightly when selected.
private struct TripPinView: View {
    let trip: Trip
    let isSelected: Bool

    var body: some View {
        VStack(spacing: -2) {
            label
                .fixedSize()

            PinTail()
                .fill(trip.theme.accentColor)
                .frame(width: 14, height: 8)
        }
        .shadow(color: .black.opacity(0.25), radius: isSelected ? 5 : 3, y: 2)
        .scaleEffect(isSelected ? 1.15 : 1, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }

    @ViewBuilder
    private var label: some View {
        let styledText = Text(trip.name)
            .font(AppFont.outfit(13, weight: .bold, relativeTo: .caption))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

        if #available(iOS 26, *) {
            styledText.glassEffect(.regular.tint(trip.theme.accentColor).interactive(), in: Capsule())
        } else {
            styledText.background(trip.theme.accentColor, in: Capsule())
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
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
            } else {
                Image(systemName: "square.and.arrow.up")
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
            }
        }
        .disabled(isGenerating)
        .accessibilityLabel("Share Map")
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct TripChipScroller: View {
    let trips: [(trip: Trip, coordinate: CLLocationCoordinate2D)]
    let selectedTripID: UUID?
    let onFocus: (Trip, CLLocationCoordinate2D) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(trips, id: \.trip.id) { entry in
                    TripChip(trip: entry.trip, isSelected: entry.trip.id == selectedTripID) {
                        onFocus(entry.trip, entry.coordinate)
                    }
                }
            }
            .padding()
        }
        .background(Color(.clear))
    }
}

private struct TripChip: View {
    let trip: Trip
    let isSelected: Bool
    let onFocus: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onFocus) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(trip.theme.accentColor)
                        .frame(width: 12, height: 12)

                    Text(trip.name)
                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            NavigationLink(value: trip) {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassOrStickerControl(
            isSelected: isSelected,
            tint: trip.theme.accentColor
        )
    }
}
