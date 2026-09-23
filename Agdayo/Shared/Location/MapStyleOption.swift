import SwiftUI
import MapKit

/// The 3 map styles offered, replacing Leaflet's OSM/Esri-satellite/hybrid tile layers.
enum MapStyleOption: String, CaseIterable, Identifiable {
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

    /// For `MKMapSnapshotter.Options`, which predates the SwiftUI `MapStyle` type.
    var mkMapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .imagery: return .satellite
        case .hybrid: return .hybrid
        }
    }
}

struct MapStylePickerButton: View {
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
        .accessibilityLabel("Map Style")
    }
}
