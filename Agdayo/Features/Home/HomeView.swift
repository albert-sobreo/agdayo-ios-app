import SwiftUI
import SwiftData

/// The app's default landing tab — a curated summary instead of the raw
/// trip list (that's still the Trips tab, for full search/browse). Owns its
/// own `NavigationPath` (same reasoning as `TripListView`): leaving a trip
/// from here should pop all the way back to Home's own root, no matter how
/// deep the leave action happened.
struct HomeView: View {
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @State private var path = NavigationPath()
    @State private var shareItem: ShareItem?
    @State private var isPresentingCreateFlow = false
    @State private var isPresentingJoinFlow = false

    /// An in-progress trip takes priority over a future one for the
    /// showcase slot — "what's happening right now" is more relevant than
    /// "what's next."
    private var showcasedTrip: Trip? {
        trips.first(where: { $0.status == .active })
            ?? trips.filter { $0.status == .upcoming }.min(by: { $0.startDate < $1.startDate })
    }

    private var otherUpcoming: [Trip] {
        trips.filter { ($0.status == .upcoming || $0.status == .active) && $0.id != showcasedTrip?.id }
    }

    private var pastTrips: [Trip] {
        trips.filter { $0.status == .completed }.sorted { $0.endDate > $1.endDate }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if showcasedTrip == nil && otherUpcoming.isEmpty && pastTrips.isEmpty {
                    VStack(spacing: 16) {
                        EmptyStateView(
                            iconName: "airplane.departure",
                            title: "No Trips Yet",
                            message: "Plan your first trip or join a friend's trip with an invite code.",
                            actionTitle: "Create a Trip",
                            action: { isPresentingCreateFlow = true }
                        )

                        Button {
                            isPresentingJoinFlow = true
                        } label: {
                            Label("Join with Code", systemImage: "ticket")
                                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.appPrimary)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            if let showcasedTrip {
                                showcaseSection(showcasedTrip)
                            }
                            if !otherUpcoming.isEmpty {
                                upcomingScroller
                            }
                            travelMapCard
                            if !pastTrips.isEmpty {
                                pastTripsSection
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .background(BackgroundImageModifier())
            .navigationTitle("Home")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip, onLeftTrip: { path = NavigationPath() })
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isPresentingCreateFlow = true
                        } label: {
                            Label("Create Trip", systemImage: "plus")
                        }
                        Button {
                            isPresentingJoinFlow = true
                        } label: {
                            Label("Join Trip with Code", systemImage: "ticket")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .sheet(item: $shareItem) { item in
                ActivityShareSheet(activityItems: [item.url])
            }
            .sheet(isPresented: $isPresentingCreateFlow) {
                NavigationStack {
                    ManualTripFormView(onSaved: { isPresentingCreateFlow = false })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { isPresentingCreateFlow = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $isPresentingJoinFlow) {
                JoinTripSheet(onJoined: { trip in path.append(trip) })
            }
        }
    }

    @ViewBuilder
    private func showcaseSection(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(trip.status == .active ? "Currently Traveling" : "Up Next")
                .font(AppFont.outfit(20, weight: .bold, relativeTo: .title3))
                .padding(.horizontal)
            NavigationLink(value: trip) {
                TripCardView(
                    name: trip.name,
                    location: trip.location,
                    theme: trip.theme,
                    startDate: trip.startDate,
                    endDate: trip.endDate,
                    status: trip.status,
                    coordinate: trip.coordinate,
                    showsMapBackground: true,
                    emphasizesTitle: true
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var upcomingScroller: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming Trips")
                .font(AppFont.outfit(18, weight: .bold, relativeTo: .title3))
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(otherUpcoming) { trip in
                        NavigationLink(value: trip) {
                            TripSummaryCardView(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private var travelMapCard: some View {
        NavigationLink {
            VisitedPlacesMapView()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Travel Map")
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                    Text("See the countries and cities you've visited.")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "globe")
                    .font(.title2)
                    .foregroundStyle(Color.appPrimary)
            }
            .padding()
            .modifier(GlassOrStickerCard(cornerRadius: AppRadius.denseCard))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var pastTripsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Past Trips")
                .font(AppFont.outfit(18, weight: .bold, relativeTo: .title3))
                .padding(.horizontal)
            VStack(spacing: 10) {
                ForEach(pastTrips) { trip in
                    Button {
                        path.append(trip)
                    } label: {
                        PastTripRow(trip: trip, onShare: { share(trip) })
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    /// A themed recap card, rendered off-screen to a flat PNG via
    /// `ImageRenderer` — simpler than `GlobalMapView`'s manual pin-drawing
    /// since there's no MapKit snapshot involved, just a styled SwiftUI view.
    private func share(_ trip: Trip) {
        let renderer = ImageRenderer(content: TripRecapCardView(trip: trip))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage, let data = uiImage.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agdayo-trip-recap-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            shareItem = ShareItem(url: url)
        } catch {
            // Sharing just won't happen this time; nothing destructive to recover from.
        }
    }
}

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// Fixed-width card for the horizontal "Upcoming Trips" scroller —
/// `TripCardView` itself is sized for a full-width list row, not a cell.
private struct TripSummaryCardView: View {
    let trip: Trip

    private var dateRangeText: String {
        let formatter = Date.FormatStyle().month(.abbreviated).day()
        return "\(trip.startDate.formatted(formatter)) – \(trip.endDate.formatted(formatter))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBadge(status: trip.status)
            Text(trip.name)
                .font(AppFont.outfit(17, weight: .bold, relativeTo: .headline))
                .foregroundStyle(trip.theme.accentColor.mix(with: .black, by: 0.35))
                .lineLimit(1)
            Label(trip.location, systemImage: "mappin.and.ellipse")
                .font(AppFont.outfit(12, relativeTo: .caption))
                .foregroundStyle(trip.theme.accentColor)
                .lineLimit(1)
            Label(dateRangeText, systemImage: "calendar")
                .font(AppFont.outfit(12, relativeTo: .caption))
                .foregroundStyle(trip.theme.accentColor)
        }
        .padding()
        .frame(width: 220, alignment: .leading)
        .modifier(GlassOrStickerCard(cornerRadius: AppRadius.denseCard))
    }
}

private struct PastTripRow: View {
    let trip: Trip
    let onShare: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name)
                    .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                Label(trip.location, systemImage: "mappin.and.ellipse")
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .padding(8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(trip.theme.accentColor)
        }
        .padding()
        .modifier(GlassOrStickerCard(cornerRadius: AppRadius.denseCard))
    }
}

/// The actual shared image — full-bleed themed background, not transparent
/// (unlike the travel-stats overlay), since this is a standalone recap
/// card, not a sticker meant to sit on top of another photo.
private struct TripRecapCardView: View {
    let trip: Trip

    private var dateRangeText: String {
        let formatter = Date.FormatStyle().month(.abbreviated).day().year()
        return "\(trip.startDate.formatted(formatter)) – \(trip.endDate.formatted(formatter))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(trip.theme.displayName.uppercased())
                .font(AppFont.outfit(12, weight: .bold, relativeTo: .caption))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.85))
            Text(trip.name)
                .font(AppFont.outfit(32, weight: .bold, relativeTo: .largeTitle))
                .foregroundStyle(.white)
            Label(trip.location, systemImage: "mappin.and.ellipse")
                .font(AppFont.outfit(16, relativeTo: .body))
                .foregroundStyle(.white.opacity(0.9))
            Label(dateRangeText, systemImage: "calendar")
                .font(AppFont.outfit(16, relativeTo: .body))
                .foregroundStyle(.white.opacity(0.9))
            Text("\(trip.numberOfDays) day\(trip.numberOfDays == 1 ? "" : "s") of adventure")
                .font(AppFont.outfit(14, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(32)
        .frame(width: 400, height: 500, alignment: .topLeading)
        .background(trip.theme.accentColor.gradient)
    }
}
