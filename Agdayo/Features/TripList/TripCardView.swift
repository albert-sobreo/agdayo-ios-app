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
    var coordinate: CLLocationCoordinate2D? = nil
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
            if status != .completed, let coordinate {
                MapBackgroundDecoration(coordinate: coordinate, locationQuery: location)
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
                    startDate: startDate,
                    endDate: endDate,
                    theme: theme
                )
            }
        }
    }
}

struct MapBackgroundDecoration: View {
    let coordinate: CLLocationCoordinate2D
    var locationQuery: String = ""

    private let visibleWidth: CGFloat = 220
    private static let oversizeFactor: CGFloat = 1.6
    private static let cityBaseSpanMeters: CLLocationDistance = 60000
    private static let countryFallbackSpanMeters: CLLocationDistance = 1_500_000
    private var oversizeFactor: CGFloat { Self.oversizeFactor }

    private var isCountryLevel: Bool {
        !locationQuery.trimmingCharacters(in: .whitespaces).contains(",")
    }

    @State private var cameraPosition: MapCameraPosition

    init(coordinate: CLLocationCoordinate2D, locationQuery: String = "") {
        self.coordinate = coordinate
        self.locationQuery = locationQuery
        _cameraPosition = State(initialValue: .region(Self.region(center: coordinate, spanMeters: Self.cityBaseSpanMeters)))
    }

    private static func region(center: CLLocationCoordinate2D, spanMeters: CLLocationDistance) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center,
            latitudinalMeters: spanMeters * oversizeFactor,
            longitudinalMeters: spanMeters * oversizeFactor
        )
    }

    var body: some View {
        GeometryReader { geometry in
            Map(position: $cameraPosition, interactionModes: [])
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
            cameraPosition = .region(Self.region(center: coordinate, spanMeters: Self.cityBaseSpanMeters))
        }
        .task(id: locationQuery) {
            guard isCountryLevel else { return }
            let geocoder = CLGeocoder()
            guard let placemark = try? await geocoder.geocodeAddressString(locationQuery).first else { return }
            if let region = placemark.region as? CLCircularRegion {
                cameraPosition = .region(Self.region(center: region.center, spanMeters: region.radius * 2))
            } else if let center = placemark.location?.coordinate {
                cameraPosition = .region(Self.region(center: center, spanMeters: Self.countryFallbackSpanMeters))
            }
        }
    }
}

private struct TripCardHeader: View {
    let name: String
    let location: String
    let theme: TripTheme
    let status: TripStatus
    var emphasizesTitle: Bool = false

    private var headline: Color {
        theme.accentColor.mix(with: .black, by: 0.35)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBadge(status: status)
                .textCase(.uppercase)
                .tracking(2)
                .padding(.horizontal)
                .padding(.top)

            VStack(alignment: .leading, spacing: 2) {
                Text(location.uppercased())
                    .font(AppFont.barlowCondensed(48, weight: .semibold, relativeTo: .title2))
                    .tracking(2)
                    .foregroundStyle(headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(name.uppercased())
                    .font(AppFont.barlowCondensed(16, weight: .semibold, relativeTo: .subheadline))
                    .tracking(2)
                    .foregroundStyle(headline)
                    .lineLimit(1)
            }
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TripCardFooter: View {
    let startDate: Date
    let endDate: Date
    let theme: TripTheme

    private var numberOfDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        return max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }

    private func monthDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().month(.abbreviated).day())
    }

    var body: some View {
        HStack(spacing: 0) {
            statColumn(label: "Depart", value: monthDay(startDate))
            verticalDivider
            statColumn(label: "Return", value: monthDay(endDate))
            verticalDivider
            statColumn(label: "Days", value: "\(numberOfDays)")
        }
        .padding()
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(theme.accentColor.opacity(0.3))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 12)
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .trackedLabel(10, color: theme.accentColor.mix(with: .black, by: 0.35).opacity(0.7))
            Text(value.uppercased())
                .font(AppFont.barlowCondensed(20, weight: .semibold))
                .foregroundStyle(theme.accentColor.mix(with: .black, by: 0.35))
        }
    }
}
