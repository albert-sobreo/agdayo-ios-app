import SwiftUI
import MapKit

/// Plots every activity with a coordinate on a map, with style switching
/// (standard/imagery/hybrid, replacing Leaflet's 3 tile layers) and a
/// bottom scroller to focus on a specific activity, mirroring SheetMap.vue.
struct TripMapView: View {
    let trip: Trip

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapStyleOption: MapStyleOption = .standard
    @State private var selectedActivityID: UUID?

    private var activitiesWithCoordinates: [Activity] {
        trip.activities.filter { $0.coordinate != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(position: $cameraPosition, selection: $selectedActivityID) {
                ForEach(activitiesWithCoordinates) { activity in
                    if let coordinate = activity.coordinate {
                        Marker(activity.title, coordinate: coordinate)
                            .tint(trip.theme.accentColor)
                            .tag(activity.id)
                    }
                }
            }
            .mapStyle(mapStyleOption.mapStyle)
            .onAppear(perform: fitAllActivities)
            .overlay(alignment: .topTrailing) {
                MapStylePicker(selection: $mapStyleOption)
                    .padding()
            }

            if !activitiesWithCoordinates.isEmpty {
                ActivityScroller(
                    activities: activitiesWithCoordinates,
                    selectedActivityID: $selectedActivityID,
                    onSelect: focus
                )
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fitAllActivities() {
        let coordinates = activitiesWithCoordinates.compactMap { $0.coordinate }
        guard !coordinates.isEmpty else { return }
        let rect = coordinates.reduce(MKMapRect.null) { partial, coordinate in
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            return partial.union(pointRect)
        }
        cameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.2 - 500, dy: -rect.height * 0.2 - 500))
    }

    private func focus(_ activity: Activity) {
        guard let coordinate = activity.coordinate else { return }
        selectedActivityID = activity.id
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
        }
    }
}

private enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard, imagery, hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: return "Street"
        case .imagery: return "Satellite"
        case .hybrid: return "Hybrid"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard: return .standard
        case .imagery: return .imagery
        case .hybrid: return .hybrid
        }
    }
}

private struct MapStylePicker: View {
    @Binding var selection: MapStyleOption

    var body: some View {
        Menu {
            ForEach(MapStyleOption.allCases) { option in
                Button(option.label) { selection = option }
            }
        } label: {
            Image(systemName: "map.fill")
                .padding(8)
                .background(.thinMaterial, in: Circle())
        }
    }
}

private struct ActivityScroller: View {
    let activities: [Activity]
    @Binding var selectedActivityID: UUID?
    let onSelect: (Activity) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                    ActivityScrollerChip(
                        number: index + 1,
                        title: activity.title,
                        isSelected: activity.id == selectedActivityID
                    ) {
                        onSelect(activity)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
}

private struct ActivityScrollerChip: View {
    let number: Int
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(.caption.bold())
                    .frame(width: 20, height: 20)
                    .background(isSelected ? Color.appPrimary : Color(.systemGray5))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .clipShape(Circle())
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
