import CoreLocation
import MapKit
import SwiftUI

/// "How to get there": Google's transit route for one leg as a list of steps
/// (walk, then which line from which stop, and so on). Google's terms don't
/// allow drawing its routes on Apple's map, so the map view is a hand-off to
/// Google Maps or Apple Maps instead.
struct TransitStepsSheet: View {
    let fromName: String
    let toName: String
    let fromCoordinate: CLLocationCoordinate2D
    let toCoordinate: CLLocationCoordinate2D
    /// When you want to arrive (the next stop's start time).
    let arriveBy: Date?
    let accentColor: Color

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var state: LoadState = .loading

    private enum LoadState {
        case loading
        case loaded(ServerRoute)
        case noRoute
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("From", value: fromName)
                    LabeledContent("To", value: toName)
                }
                content
                Section {
                    Button("Open in Google Maps", systemImage: "globe", action: openGoogleMaps)
                    Button("Open in Apple Maps", systemImage: "map", action: openAppleMaps)
                }
            }
            .navigationTitle("How to get there")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            Section {
                HStack {
                    ProgressView()
                    Text("Asking Google for the route…").foregroundStyle(.secondary)
                }
            }
        case .noRoute:
            Section {
                Label("Google has no transit route here. Walking or a car is the way to go.", systemImage: "tram.circle")
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("Try again") { Task { await load() } }
            }
        case .loaded(let route):
            Section {
                summary(route)
            }
            Section("Steps") {
                ForEach(Array(route.steps.enumerated()), id: \.offset) { _, step in
                    StepRow(step: step, accentColor: accentColor)
                }
            }
            Section {
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if route.timeAdjusted {
                        Text("Google has no timetable for that day yet, so these are today's times. Lines and stops are usually the same.")
                    }
                    Text("Powered by Google · checked \(route.fetchedAt.formatted(date: .omitted, time: .shortened))")
                }
            }
        }
    }

    private func summary(_ route: ServerRoute) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(TravelFormat.duration(route.durationSeconds)) · \(TravelFormat.distance(route.distanceMeters))")
                .font(AppFont.outfit(17, weight: .semibold, relativeTo: .headline))
            if let departure = route.firstDeparture, !route.timeAdjusted {
                Text("First ride leaves at \(departure.formatted(date: .omitted, time: .shortened))")
                    .font(AppFont.outfit(14, relativeTo: .subheadline))
                    .foregroundStyle(accentColor)
            }
            if let fare = route.fare {
                Text("Fare \(fare.text ?? fare.amount.formatted(.currency(code: fare.currency)))")
                    .font(AppFont.outfit(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            if let route = try await AgdayoServer.transitRoute(from: fromCoordinate, to: toCoordinate, arriveBy: arriveBy) {
                state = .loaded(route)
            } else {
                state = .noRoute
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func openGoogleMaps() {
        guard let url = TravelPlanning.googleMapsURL(from: fromCoordinate, to: toCoordinate, mode: .transit) else { return }
        openURL(url)
    }

    private func openAppleMaps() {
        let source = MKMapItem(placemark: MKPlacemark(coordinate: fromCoordinate))
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: toCoordinate))
        source.name = fromName
        destination.name = toName
        MKMapItem.openMaps(with: [source, destination], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
    }
}

private struct StepRow: View {
    let step: ServerRoute.Step
    let accentColor: Color

    var body: some View {
        if let leg = step.transit {
            transitRow(leg)
        } else {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.instruction ?? "Walk")
                        .font(AppFont.outfit(15, relativeTo: .body))
                    Text("\(TravelFormat.duration(step.durationSeconds)) · \(TravelFormat.distance(step.distanceMeters))")
                        .font(AppFont.outfit(13, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: step.kind == "walk" ? "figure.walk" : "arrow.turn.up.right")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func transitRow(_ leg: ServerRoute.TransitLeg) -> some View {
        let lineColor = Color(hexString: leg.color) ?? accentColor
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: Self.symbol(for: leg.vehicle))
                .foregroundStyle(lineColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(leg.lineShortName ?? leg.lineName)
                        .font(AppFont.outfit(13, weight: .bold, relativeTo: .caption))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(lineColor, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Color(hexString: leg.textColor) ?? .white)
                    if let headsign = leg.headsign {
                        Text("towards \(headsign)")
                            .font(AppFont.outfit(13, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                stop(leg.departureStop, time: leg.departureTime, verb: "Board at")
                if let count = leg.stopCount {
                    Text(count == 1 ? "1 stop" : "\(count) stops")
                        .font(AppFont.outfit(13, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
                stop(leg.arrivalStop, time: leg.arrivalTime, verb: "Get off at")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func stop(_ name: String, time: Date?, verb: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(verb) \(name)")
                .font(AppFont.outfit(15, relativeTo: .body))
            Spacer(minLength: 8)
            if let time {
                Text(time.formatted(date: .omitted, time: .shortened))
                    .font(AppFont.outfit(13, weight: .semibold, relativeTo: .caption))
                    .monospacedDigit()
            }
        }
    }

    static func symbol(for vehicle: String) -> String {
        switch vehicle.lowercased() {
        case let name where name.contains("bus"): return "bus.fill"
        case let name where name.contains("ferry"): return "ferry.fill"
        case let name where name.contains("tram") || name.contains("light rail"): return "lightrail.fill"
        case let name where name.contains("subway") || name.contains("metro"): return "tram.fill"
        case let name where name.contains("cable") || name.contains("gondola"): return "cablecar.fill"
        default: return "train.side.front.car"
        }
    }
}

extension Color {
    /// "#RRGGBB" from Google's line colours; nil when missing or malformed.
    init?(hexString: String?) {
        guard let hexString else { return nil }
        let digits = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(hex: value)
    }
}
