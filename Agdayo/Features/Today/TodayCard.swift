import MapKit
import SwiftData
import SwiftUI

/// Home's card during a trip: where you're going next, when to leave, and
/// one tap to the steps or a maps app. Travel is timed from where you are
/// when location is allowed, else from the previous stop or your stay.
struct TodayCard: View {
    let trip: Trip

    @Query private var activities: [Activity]
    @Query private var stays: [Accommodation]
    @Environment(\.openURL) private var openURL

    @State private var location = OneShotLocation()
    @State private var now = Date.now
    @State private var leg: Leg?
    @State private var isLoading = false
    @State private var showingSteps = false

    /// The worked-out trip to the next stop.
    private struct Leg: Equatable {
        let activityID: UUID
        let from: CLLocationCoordinate2D
        let fromName: String
        let usedLocation: Bool
        let mode: MKDirectionsTransportType
        let estimate: TravelEstimate

        static func == (a: Leg, b: Leg) -> Bool {
            a.activityID == b.activityID && a.mode == b.mode && a.estimate.duration == b.estimate.duration && a.usedLocation == b.usedLocation
        }
    }

    init(trip: Trip) {
        self.trip = trip
        let tripID = trip.id
        _activities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID }, sort: \Activity.date)
        _stays = Query(filter: #Predicate<Accommodation> { $0.trip?.id == tripID })
    }

    private var plan: TodayPlan { TodayPlan(activities: activities, stays: stays, now: now) }
    private var accent: Color { trip.theme.accentColor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .trackedLabel(color: .secondary)
            if let next = plan.next {
                nextStop(next)
                if !plan.laterToday.isEmpty {
                    Divider()
                    laterToday
                }
            } else {
                Text("Nothing else planned on this trip.")
                    .font(AppFont.outfit(14, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        .task(id: plan.next?.id) { await loadLeg() }
        .task {
            // Keeps "Leave in 12 min" counting down while Home is open.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = .now
            }
        }
        .onChange(of: location.authorizationStatus) { Task { await loadLeg() } }
        .sheet(isPresented: $showingSteps) {
            if let next = plan.next, let leg, let to = next.coordinate {
                TransitStepsSheet(
                    fromName: leg.usedLocation ? "Your location" : leg.fromName,
                    toName: next.title,
                    fromCoordinate: leg.from,
                    toCoordinate: to,
                    arriveBy: next.date,
                    accentColor: accent
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func nextStop(_ next: Activity) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: next.iconName)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(next.title)
                    .font(AppFont.outfit(17, weight: .semibold, relativeTo: .headline))
                Text(startText(next))
                    .font(AppFont.outfit(13, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
                if !next.location.isEmpty {
                    Text(next.location)
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }

        if next.coordinate == nil {
            Label("Add a map pin to this stop to see when to leave.", systemImage: "mappin.slash")
                .font(AppFont.outfit(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
        } else if let leg, leg.activityID == next.id {
            leaveRow(next: next, leg: leg)
        } else if isLoading {
            ProgressView().controlSize(.small)
        } else {
            Text("Couldn't work out the travel time.")
                .font(AppFont.outfit(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
        }

        if location.canAsk {
            Button {
                location.requestPermission()
            } label: {
                Label("Time it from where I am", systemImage: "location")
                    .font(AppFont.outfit(12, weight: .medium, relativeTo: .caption))
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
        }
    }

    @ViewBuilder
    private func leaveRow(next: Activity, leg: Leg) -> some View {
        let leaveBy = TravelPlanning.leaveBy(arrival: next.date, travelTime: leg.estimate.duration, spare: TravelPlanning.leaveBySpare)
        let status = TodayPlan.leaveText(leaveBy: leaveBy, now: now)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.text)
                    .font(AppFont.barlowCondensed(26, weight: .semibold, relativeTo: .title2))
                    .foregroundStyle(status.isLate ? .orange : accent)
                Spacer()
                Text("\(TravelFormat.duration(leg.estimate.duration)) \(leg.mode.travelPhrase)")
                    .font(AppFont.outfit(13, relativeTo: .subheadline))
                    .foregroundStyle(.secondary)
            }
            Text(leg.usedLocation ? "From where you are" : "From \(leg.fromName)")
                .font(AppFont.outfit(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if leg.mode == .transit {
                    Button { showingSteps = true } label: {
                        Label("Steps", systemImage: "list.bullet")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Menu {
                    Button("Apple Maps", systemImage: "map") { openAppleMaps(to: next, leg: leg) }
                    Button("Google Maps", systemImage: "globe") { openGoogleMaps(to: next, leg: leg) }
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.bordered)
            }
            .font(AppFont.outfit(13, weight: .semibold, relativeTo: .subheadline))
            .tint(accent)
        }
    }

    private var laterToday: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Later today")
                .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(.secondary)
            ForEach(plan.laterToday) { activity in
                HStack(spacing: 10) {
                    Text(activity.date, format: .dateTime.hour().minute())
                        .font(AppFont.barlowCondensed(16, weight: .semibold))
                        .frame(width: 64, alignment: .leading)
                    Text(activity.title)
                        .font(AppFont.outfit(14, relativeTo: .subheadline))
                        .lineLimit(1)
                }
            }
        }
    }

    private func startText(_ next: Activity) -> String {
        let time = next.date.formatted(date: .omitted, time: .shortened)
        if plan.nextIsTomorrowOrLater {
            return "\(next.date.formatted(.dateTime.weekday(.wide))) at \(time)"
        }
        return "Starts at \(time)"
    }

    // MARK: Travel

    private func loadLeg() async {
        guard let next = plan.next, let to = next.coordinate else {
            leg = nil
            return
        }
        isLoading = true
        defer { isLoading = false }
        var origin: (name: String, coordinate: CLLocationCoordinate2D, usedLocation: Bool)?
        if let here = await location.current() {
            origin = ("Your location", here, true)
        } else if let fallback = plan.fallbackOrigin {
            origin = (fallback.name, fallback.coordinate, false)
        }
        guard let origin else {
            leg = nil
            return
        }
        var mode: MKDirectionsTransportType? = TravelPlanning.initialMode(from: origin.coordinate, to: to)
        while let current = mode {
            if let estimate = try? await TravelEstimateService.estimate(from: origin.coordinate, to: to, transportType: current) {
                let found = Leg(activityID: next.id, from: origin.coordinate, fromName: origin.name, usedLocation: origin.usedLocation, mode: current, estimate: estimate)
                leg = found
                NotificationScheduler.scheduleLeaveBy(for: next, travelTime: estimate.duration, mode: current)
                return
            }
            mode = TravelPlanning.fallbackMode(after: current)
        }
        leg = nil
    }

    private func openAppleMaps(to next: Activity, leg: Leg) {
        guard let to = next.coordinate else { return }
        let source = leg.usedLocation ? MKMapItem.forCurrentLocation() : MKMapItem(placemark: MKPlacemark(coordinate: leg.from))
        if !leg.usedLocation { source.name = leg.fromName }
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        destination.name = next.title
        MKMapItem.openMaps(with: [source, destination], launchOptions: [MKLaunchOptionsDirectionsModeKey: leg.mode.mapsLaunchMode])
    }

    private func openGoogleMaps(to next: Activity, leg: Leg) {
        guard let to = next.coordinate,
              let url = TravelPlanning.googleMapsURL(from: leg.from, to: to, mode: leg.mode) else { return }
        openURL(url)
    }
}
