import SwiftUI
import SwiftData

/// The app's default landing tab — a curated summary instead of the raw
/// trip list (that's still the Trips tab, for full search/browse). Owns its
/// own `NavigationPath` (same reasoning as `TripListView`): leaving a trip
/// from here should pop all the way back to Home's own root, no matter how
/// deep the leave action happened.
struct HomeView: View {
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    /// Queried separately rather than read via `trip.activities` — that
    /// relationship traversal doesn't reliably reflect edits made
    /// elsewhere in the app without a round trip through navigation (see
    /// `TripDetailView`'s own `activities` query for the same workaround).
    @Query(sort: \Activity.date) private var allActivities: [Activity]
    @State private var path = NavigationPath()
    @State private var shareItem: ShareItem?
    @State private var isPresentingCreateFlow = false
    @State private var isPresentingJoinFlow = false
    /// Captured once from the ambient layout (status bar + nav bar height)
    /// before the scroll content ignores it — used to push the showcase
    /// card's text back down below that area while its background bleeds
    /// all the way to the top of the screen.
    @State private var topSafeAreaInset: CGFloat = 0
    @State private var showsAllPastTrips = false

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

    /// How many past trips Home shows before "Show all".
    private let pastTripLimit = 3

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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(BrandPalette.canvas.ignoresSafeArea())
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            if let showcasedTrip {
                                showcaseSection(showcasedTrip, topInset: topSafeAreaInset)
                            } else {
                                showcaseEmptyState(topInset: topSafeAreaInset)
                            }
                            if !otherUpcoming.isEmpty {
                                upcomingScroller
                            }
                            travelMapCard
                            if !pastTrips.isEmpty {
                                pastTripsSection
                            }
                        }
                        .padding(.bottom)
                    }
                    .scrollClipDisabled()
                    .ignoresSafeArea(edges: .top)
                    .background(BrandPalette.canvas.ignoresSafeArea())
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.top
            } action: { newValue in
                topSafeAreaInset = newValue
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
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

    private func dayNumber(for trip: Trip) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.startOfDay(for: trip.startDate)
        return max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
    }

    /// The nearest two activities still ahead of right now, regardless of
    /// which day they fall on — good enough for a dashboard glance (compare
    /// to `TripLiveActivityCoordinator`'s stricter "today only" version,
    /// which needs to stay in sync with a "Day N" label mid-activity).
    private func nextActivities(for trip: Trip) -> [Activity] {
        Array(allActivities.filter { $0.trip?.id == trip.id && $0.date > .now }.prefix(2))
    }

    private func dateRangeText(_ trip: Trip) -> String {
        let formatter = Date.FormatStyle().month(.abbreviated).day()
        return "\(trip.location) · \(trip.startDate.formatted(formatter)) → \(trip.endDate.formatted(formatter))"
    }

    private func timeParts(_ date: Date) -> (time: String, meridiem: String, monthDay: String) {
        let time = DateFormatter()
        time.dateFormat = "hh:mm"
        let meridiem = DateFormatter()
        meridiem.dateFormat = "a"
        let monthDay = DateFormatter()
        monthDay.dateFormat = "M/dd"
        return (time.string(from: date), meridiem.string(from: date).lowercased(), monthDay.string(from: date))
    }

    private func dashedDivider(color: Color) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay(
                Rectangle()
                    .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
    }

    @ViewBuilder
    private func showcaseSection(_ trip: Trip, topInset: CGFloat) -> some View {
        let headline = trip.theme.accentColor.mix(with: .black, by: 0.35)
        NavigationLink(value: trip) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: 0){
                    HStack {
                        if trip.status == .active {
                            PillTag(
                                text: "Active · Day \(dayNumber(for: trip)) of \(trip.numberOfDays)"
                                    .uppercased(),
                                background: trip.theme.lightTintColor,
                                foreground: trip.theme.accentColor
                            )
                        } else {
                            StatusBadge(status: trip.status)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(headline)
                    }

                    Text(trip.name.uppercased())
                        .font(AppFont.barlowCondensed(32, weight: .semibold, relativeTo: .largeTitle))
                        .tracking(2)
                        .foregroundStyle(headline)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                }

                Text(dateRangeText(trip).uppercased())
                    .font(AppFont.barlowCondensed(20, weight: .regular))
                    .tracking(2)

                dashedDivider(color: trip.theme.accentColor)

                let upcomingActivities = nextActivities(for: trip)
                if !upcomingActivities.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Next Up")
                            .trackedLabel(color: headline.opacity(0.65))
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(upcomingActivities) { activity in
                                let parts = timeParts(activity.date)
                                HStack(alignment: .center, spacing: AppSpacing.md) {
                                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                                        Text(parts.time)
                                            .font(AppFont.barlowCondensed(32, weight: .semibold))
                                            .tracking(2)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(parts.monthDay)
                                                .font(AppFont.outfit(8, weight: .light))
                                                .tracking(0.5)
                                                .opacity(0.6)
                                            Text(parts.meridiem)
                                                .font(AppFont.outfit(11, weight: .semibold))
                                                .tracking(2)
                                                .textCase(.uppercase)
                                        }
                                        .alignmentGuide(.firstTextBaseline) { dimensions in
                                            dimensions[.bottom]
                                        }
                                    }
                                    .foregroundStyle(headline)
                                    .frame(width: 108, alignment: .leading)
                                    VStack(alignment: .leading, spacing: -2){
                                        Text(activity.title)
                                            .font(AppFont.outfit(15, weight: .semibold))
                                            .foregroundStyle(headline)
                                        if !activity.location.isEmpty {
                                            Text(activity.location)
                                                .font(AppFont.outfit(11, relativeTo: .caption))
                                                .foregroundStyle(.primary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                }
                .padding(.horizontal)
                .padding(.top, topInset + AppSpacing.md)
                .padding(.bottom)
                .background(alignment: .trailing) {
                    ZStack(alignment: .trailing) {
                        trip.theme.headerBackground
                        if let coordinate = trip.coordinate {
                            MapBackgroundDecoration(coordinate: coordinate, locationQuery: trip.location)
                        }
                    }
                }
        }
        .buttonStyle(.plain)
    }

    /// Stands in for `showcaseSection` whenever there's no active/upcoming
    /// trip to feature — keeps the same top padding/background structure
    /// as a real showcase card so this is still the first thing in the
    /// scroll content and the page doesn't render behind the header.
    @ViewBuilder
    private func showcaseEmptyState(topInset: CGFloat) -> some View {
        EmptyStateView(
            iconName: "airplane.departure",
            title: "No Upcoming Trips",
            message: "Plan your next trip or join a friend's trip with an invite code.",
            actionTitle: "Create a Trip",
            action: { isPresentingCreateFlow = true },
            secondaryActionTitle: "Join with Code",
            secondaryAction: { isPresentingJoinFlow = true }
        )
        .padding(.horizontal)
        .padding(.top, topInset + AppSpacing.md)
        .padding(.bottom, AppSpacing.lg)
        .background(BrandPalette.blush)
    }

    @ViewBuilder
    private var upcomingScroller: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upcoming")
                .textCase(.uppercase)
                .font(AppFont.barlowCondensed(36, weight: .regular, relativeTo: .title2))
                .padding(.horizontal)
                .tracking(2)
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
                .textCase(.uppercase)
                .font(AppFont.barlowCondensed(36, weight: .regular, relativeTo: .title2))
                .padding(.horizontal)
                .tracking(2)
            VStack(spacing: 10) {
                ForEach(showsAllPastTrips ? pastTrips : Array(pastTrips.prefix(pastTripLimit))) { trip in
                    Button {
                        path.append(trip)
                    } label: {
                        PastTripRow(trip: trip, onShare: { share(trip) })
                    }
                    .buttonStyle(.plain)
                }

                // Only the most recent few are shown; the rest are one tap away.
                if pastTrips.count > pastTripLimit {
                    Button {
                        withAnimation { showsAllPastTrips.toggle() }
                    } label: {
                        Text(showsAllPastTrips ? "Show less" : "Show all \(pastTrips.count) past trips")
                            .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.primary)
                            .modifier(GlassOrStickerCard(cornerRadius: AppRadius.denseCard))
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

    private var headline: Color {
        trip.theme.accentColor.mix(with: .black, by: 0.35)
    }

    private var numberOfDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: trip.startDate)
        let end = calendar.startOfDay(for: trip.endDate)
        return max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }

    private func monthDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBadge(status: trip.status)
                .textCase(.uppercase)
                .tracking(2)

            VStack(alignment: .leading, spacing: 2) {
                Text(trip.location.uppercased())
                    .font(AppFont.barlowCondensed(24, weight: .bold, relativeTo: .headline))
                    .tracking(1)
                    .foregroundStyle(headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(trip.name.uppercased())
                    .font(AppFont.barlowCondensed(11, weight: .semibold, relativeTo: .caption))
                    .tracking(2)
                    .foregroundStyle(headline)
                    .lineLimit(1)
            }

            HStack(spacing: 0) {
                statColumn(label: "Depart", value: monthDay(trip.startDate))
                verticalDivider
                statColumn(label: "Return", value: monthDay(trip.endDate))
                verticalDivider
                statColumn(label: "Days", value: "\(numberOfDays)")
            }
        }
        .padding()
        .frame(width: 220, alignment: .leading)
        .modifier(GlassOrStickerCard(cornerRadius: AppRadius.denseCard))
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(trip.theme.accentColor.opacity(0.3))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 6)
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .trackedLabel(8, color: headline.opacity(0.7))
            Text(value.uppercased())
                .font(AppFont.barlowCondensed(14, weight: .semibold))
                .foregroundStyle(headline)
        }
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
