import SwiftUI
import MapKit
import SwiftData

/// Map tab root — aggregates every trip's activities onto one map,
/// each annotation colored by its trip's theme.
struct GlobalMapView: View {
    @Query(sort: \Trip.startDate) private var trips: [Trip]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedActivityID: UUID?
    @State private var mapStyleOption: MapStyleOption = .standard

    private var activitiesWithCoordinates: [Activity] {
        trips.flatMap { $0.activities }.filter { $0.coordinate != nil }
    }

    var body: some View {
        Group {
            if activitiesWithCoordinates.isEmpty {
                EmptyStateView(
                    iconName: "map",
                    title: "No Pinned Activities Yet",
                    message: "Activities with a location will show up here once you add them to a trip's itinerary."
                )
            } else {
                Map(position: $cameraPosition, selection: $selectedActivityID) {
                    ForEach(activitiesWithCoordinates) { activity in
                        if let coordinate = activity.coordinate {
                            Marker(activity.title, coordinate: coordinate)
                                .tint(activity.trip?.theme.accentColor ?? .gray)
                                .tag(activity.id)
                        }
                    }
                }
                .mapStyle(mapStyleOption.mapStyle)
                .onAppear(perform: fitAllActivities)
                .overlay(alignment: .topTrailing) {
                    MapStylePickerButton(selection: $mapStyleOption)
                        .padding()
                }
            }
        }
        .navigationTitle("Map")
    }

    private func fitAllActivities() {
        let coordinates = activitiesWithCoordinates.compactMap { $0.coordinate }
        guard !coordinates.isEmpty else { return }
        let rect = coordinates.reduce(MKMapRect.null) { partial, coordinate in
            let point = MKMapPoint(coordinate)
            return partial.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        cameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.2 - 500, dy: -rect.height * 0.2 - 500))
    }
}
