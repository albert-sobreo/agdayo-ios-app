import CoreLocation
import MapKit
import SwiftUI

struct TripCardView: View {
    let name: String
    let location: String
    let theme: TripTheme
    let startDate: Date
    let endDate: Date
    let status: TripStatus
    /// Only rendered when both this and `showsMapBackground` are set — kept
    /// off by default so `TripListView`'s plain list rows are unaffected;
    /// only `HomeView`'s showcase card opts in.
    var coordinate: CLLocationCoordinate2D? = nil
    var showsMapBackground: Bool = false
    /// Bigger, extra-bold title — off by default (`TripListView`'s rows
    /// keep the standard size); `HomeView`'s single showcase card opts in
    /// since it has the space and prominence to justify it.
    var emphasizesTitle: Bool = false

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                content
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))
                    .glassEffect(
                        .regular.tint(theme.accentColor.opacity(0.10)),
                        in: .rect(cornerRadius: AppRadius.card)
                    )
            } else {
                content.stickerCard(
                    cornerRadius: AppRadius.card,
                    borderColor: theme.accentColor.opacity(0.3),
                    shadowColor: theme.accentColor.opacity(0.2)
                )
            }
        }
    }

    private var content: some View {
        ZStack(alignment: .trailing) {
            if showsMapBackground, let coordinate {
                MapBackgroundDecoration(coordinate: coordinate, theme: theme)
            }

            VStack(alignment: .leading, spacing: 0) {
                TripCardHeader(
                    name: name,
                    location: location,
                    theme: theme,
                    status: status,
                    emphasizesTitle: emphasizesTitle
                )

                TripCardFooter(
                    location: location,
                    startDate: startDate,
                    endDate: endDate,
                    theme: theme
                )
            }
        }
    }
}

/// A small, non-interactive map pinned to the trip's destination, faded
/// into the card's right edge — purely decorative, so interaction is fully
/// disabled to avoid fighting the card's own tap/navigation gesture.
///
/// Spans the *full* height of the card (via `GeometryReader`, since the
/// card's height comes from its sibling `VStack` and isn't known ahead of
/// time) rather than a fixed square — a fixed-height square only covered
/// the middle of a taller card, leaving a hard seam above/below where the
/// plain card background met the map's clipped edge.
private struct MapBackgroundDecoration: View {
    let coordinate: CLLocationCoordinate2D
    let theme: TripTheme

    /// The visible, faded column's width; height comes from the card itself.
    private let visibleWidth: CGFloat = 220
    /// Apple's attribution logo is required and can't be turned off via
    /// API, so instead the map is rendered this much larger than the
    /// visible column and centered — the excess (which always includes
    /// whichever corner the logo lands in) gets clipped away by the
    /// smaller outer frame below. The region's span is scaled up by the
    /// same factor so the cropped, visible portion still shows the same
    /// real-world area as an un-cropped map would, instead of looking
    /// more zoomed in.
    private static let oversizeFactor: CGFloat = 1.6
    private static let baseSpanMeters: CLLocationDistance = 8000
    private var oversizeFactor: CGFloat { Self.oversizeFactor }

    /// `Map(initialPosition:)` only seeds the camera once, on first
    /// creation — since `HomeView`'s showcase card keeps the same view
    /// identity across re-renders (same position in the tree), switching
    /// to a different trip after leaving the current one changed
    /// `coordinate` but left the already-created map's camera pointed at
    /// the old trip. Driving the camera through this `@State` + the
    /// `onChange` below re-centers it explicitly whenever `coordinate`
    /// actually changes.
    @State private var cameraPosition: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D, theme: TripTheme) {
        self.coordinate = coordinate
        self.theme = theme
        _cameraPosition = State(initialValue: .region(Self.region(for: coordinate)))
    }

    private static func region(for coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: baseSpanMeters * oversizeFactor,
            longitudinalMeters: baseSpanMeters * oversizeFactor
        )
    }

    var body: some View {
        GeometryReader { geometry in
            Map(position: $cameraPosition, interactionModes: []) {
                Marker("", coordinate: coordinate)
                    .tint(theme.accentColor)
            }
            .allowsHitTesting(false)
            .frame(width: geometry.size.width * oversizeFactor, height: geometry.size.height * oversizeFactor)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .frame(width: visibleWidth)
        .clipped()
        .mask(
            LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
        )
        .opacity(0.75)
        // `CLLocationCoordinate2D` isn't `Equatable`, so `onChange` keys off
        // a plain comparable pair of its components instead.
        .onChange(of: [coordinate.latitude, coordinate.longitude]) { _, _ in
            cameraPosition = .region(Self.region(for: coordinate))
        }
    }
}

private struct TripCardHeader: View {
    let name: String
    let location: String
    let theme: TripTheme
    let status: TripStatus
    var emphasizesTitle: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBadge(status: status)
                .padding(.horizontal)
                .padding(.top)

            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(AppFont.outfit(emphasizesTitle ? 32 : 26, weight: emphasizesTitle ? .heavy : .bold, relativeTo: .title2))
                    .foregroundStyle(
                        theme.accentColor.mix(with: .black, by: 0.35)
                    )
                    .lineLimit(1)
                Text(location)
                    .font(AppFont.outfit(14, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(
                        theme.accentColor.mix(with: .black, by: 0.35)
                    )
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TripCardFooter: View {
    let location: String
    let startDate: Date
    let endDate: Date
    let theme: TripTheme

    private var dateRangeText: String {
        let formatter = Date.FormatStyle().month(.abbreviated).day()
        return "\(startDate.formatted(formatter)) – \(endDate.formatted(formatter))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(dateRangeText, systemImage: "calendar")
            Label(location, systemImage: "mappin.and.ellipse")
        }
        .font(AppFont.outfit(12, weight: .medium, relativeTo: .caption))
        .foregroundStyle(theme.accentColor)
        .padding()
    }
}
