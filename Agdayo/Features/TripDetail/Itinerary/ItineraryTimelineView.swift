import SwiftUI
import MapKit
import CoreLocation
import SwiftData

struct ItineraryTimelineView: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []
    /// True when inlined in `TripDetailView`'s own ScrollView. A `List` has no
    /// intrinsic height there and collapses to nothing, so the embedded copy
    /// uses a plain stack; swipe-to-delete lives on the pushed full screen.
    var isEmbedded = false
    /// When set, the full screen opens scrolled to this day.
    var scrollToDay: Date?

    /// A live query scoped to this trip, not a `trip.activities` traversal —
    /// SwiftData's Observation tracking for to-many relationships doesn't
    /// reliably fire when the inverse side is set by a newly-inserted child
    /// (exactly what `ActivityEditSheet.save()` does), so this view would
    /// otherwise only refresh the next time something unrelated forced a
    /// re-render (e.g. popping and re-pushing this screen). `@Query`'s
    /// invalidation is driven by the persistent store itself, so it doesn't
    /// have that gap.
    @Query private var activities: [Activity]
    /// Same live-query reasoning as `activities`. Transport and stays are
    /// shown in the timeline straight from their own records, so editing one
    /// updates the itinerary and nothing is ever copied into an `Activity`.
    @Query private var transportSegments: [TransportSegment]
    @Query private var accommodations: [Accommodation]

    @State private var isAddingActivity = false
    /// Refreshed every minute so the "Now" marker moves while the screen is open.
    @State private var now = Date.now
    /// Non-nil while the Plan My Day sheet is up; a nil `day` means "pick one for me".
    @State private var planRequest: PlanRequest?
    @Environment(StoreService.self) private var store
    @State private var lockedFeature: PaidFeature?

    private struct PlanRequest: Identifiable {
        let id = UUID()
        let day: Date?
    }

    /// Plan My Day is part of the full unlock.
    private func startPlanning(day: Date?) {
        if store.isUnlocked {
            planRequest = PlanRequest(day: day)
        } else {
            lockedFeature = .planMyDay
        }
    }

    init(trip: Trip, memberProfiles: [AppUserProfile] = [], isEmbedded: Bool = false, scrollToDay: Date? = nil) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        self.isEmbedded = isEmbedded
        self.scrollToDay = scrollToDay
        let tripID = trip.id
        _activities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID }, sort: \Activity.date)
        _transportSegments = Query(filter: #Predicate<TransportSegment> { $0.trip?.id == tripID })
        _accommodations = Query(filter: #Predicate<Accommodation> { $0.trip?.id == tripID })
    }

    /// Activities, transport departures and hotel check-in/out, all in one list.
    private var allEntries: [ItineraryEntry] {
        activities.map(ItineraryEntry.activity)
            + transportSegments.map(ItineraryEntry.transport)
            + transportSegments.filter { $0.arrivalDateTime != nil }.map(ItineraryEntry.arrival)
            + accommodations.flatMap { [ItineraryEntry.checkIn($0), ItineraryEntry.checkOut($0)] }
    }

    /// Every trip day is listed; empty days get a "Plan my day" row.
    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allEntries) { calendar.startOfDay(for: $0.time) }
        let days = Set(trip.calendarDays).union(grouped.keys)
        return days.sorted().map { day in
            DayGroup(day: day, entries: (grouped[day] ?? []).sorted { ItineraryOrder.precedes($0.orderKey, $1.orderKey) })
        }
    }

    private func dayTitle(for day: Date) -> String {
        trip.dayTitle(for: day)
    }

    /// The time to mark on today's day, or nil when the trip isn't in progress.
    private var nowMarker: Date? {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: trip.startDate)
        guard let afterLast = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: trip.endDate)) else { return nil }
        return (first..<afterLast).contains(now) ? now : nil
    }

    @ViewBuilder
    private var content: some View {
        if activities.isEmpty && transportSegments.isEmpty && accommodations.isEmpty {
            ScrollView {
                EmptyStateView(
                    iconName: "note.text",
                    title: "No Activities Yet",
                    message: "Add your first stop to start building the itinerary.",
                    actionTitle: "Add Activity",
                    action: { isAddingActivity = true },
                    secondaryActionTitle: "Plan My Day",
                    secondaryAction: { startPlanning(day: nil) }
                )
                .padding(.top, 60)
            }
            .background {
                // Full-screen only; embedded in the trip screen it sits on that screen's own background.
                if !isEmbedded { BrandPalette.canvas.ignoresSafeArea() }
            }
        } else {
            if isEmbedded {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(dayGroups.enumerated()), id: \.element.day) { index, group in
                        DaySection(
                            dayTitle: dayTitle(for: group.day),
                            group: group,
                            trip: trip,
                            memberProfiles: memberProfiles,
                            now: nowMarker,
                            isEmbedded: true,
                            onPlanDay: { startPlanning(day: group.day) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            } else {
                // A `List` (not a ScrollView + LazyVStack) so rows get native
                // swipe-to-delete, like the trips list.
                ScrollViewReader { proxy in
                List {
                    ForEach(Array(dayGroups.enumerated()), id: \.element.day) { index, group in
                        DaySection(
                            dayTitle: dayTitle(for: group.day),
                            group: group,
                            trip: trip,
                            memberProfiles: memberProfiles,
                            now: nowMarker,
                            isEmbedded: false,
                            onPlanDay: { startPlanning(day: group.day) }
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(BrandPalette.canvas.ignoresSafeArea())
                .task {
                    // Sections are keyed by the start of their day (see the ForEach).
                    guard let scrollToDay else { return }
                    let day = Calendar.current.startOfDay(for: scrollToDay)
                    guard dayGroups.contains(where: { $0.day == day }) else { return }
                    // Give the list a moment to lay out before jumping.
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation { proxy.scrollTo(day, anchor: .top) }
                }
                }
            }
        }
    }

    var body: some View {
        content
        .navigationTitle("Itinerary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Activity", systemImage: "plus") { isAddingActivity = true }
                    Button("Plan My Day", systemImage: "wand.and.stars") { startPlanning(day: nil) }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add to Itinerary")
            }
        }
        .task {
            // Re-read the clock each minute; ends when the screen goes away.
            while !Task.isCancelled {
                now = .now
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .sheet(item: $planRequest) { request in
            PlanMyDaySheet(trip: trip, initialDay: request.day)
        }
        .paywall($lockedFeature)
        .sheet(isPresented: $isAddingActivity) {
            // From the live query, not `trip.activities`, so an activity added a
            // moment ago is always counted.
            ActivityEditSheet(trip: trip, memberProfiles: memberProfiles, latestActivityDate: activities.map(\.date).max())
        }
    }
}

private struct DaySection: View {
    let dayTitle: String
    let group: DayGroup
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []
    /// The current time while the trip is in progress, else nil. Only the
    /// day it falls on shows the "Now" marker.
    var now: Date?
    /// Inline in the trip screen's own scroll view (a card), or a section of
    /// the full-screen list.
    let isEmbedded: Bool
    var onPlanDay: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    /// The figure each travel row is showing, keyed by row, for the day's total.
    @State private var legEstimates: [String: TravelEstimate] = [:]

    private var travelTotal: (duration: TimeInterval, distance: CLLocationDistance)? {
        guard !legEstimates.isEmpty else { return nil }
        let duration = legEstimates.values.reduce(TimeInterval(0)) { $0 + $1.duration }
        let distance = legEstimates.values.reduce(CLLocationDistance(0)) { $0 + $1.distance }
        return (duration, distance)
    }

    /// Also turns the next stop's reminder into a leave-by one, now that the
    /// travel time is known.
    private func reportAndRemind(_ key: String, for activity: Activity) -> (TravelEstimate?) -> Void {
        { estimate in
            legEstimates[key] = estimate
            if let estimate {
                NotificationScheduler.scheduleLeaveBy(for: activity, travelTime: estimate.duration, mode: estimate.mode)
            }
        }
    }

    /// Corner radius of a day's card, in both the inline and full-screen lists.
    private let cardRadius: CGFloat = 20

    /// A day's card is drawn row by row in the full-screen list: only its first
    /// row rounds the top corners and only its last rounds the bottom ones.
    private func cardBackground(isTop: Bool, isBottom: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: isTop ? cardRadius : 0,
            bottomLeadingRadius: isBottom ? cardRadius : 0,
            bottomTrailingRadius: isBottom ? cardRadius : 0,
            topTrailingRadius: isTop ? cardRadius : 0
        )
        .fill(Color(.secondarySystemGroupedBackground))
        .padding(.horizontal, 16)
    }

    var body: some View {
        if isEmbedded {
            VStack(alignment: .leading, spacing: 8) {
                header
                    .padding(.horizontal, 4)
                VStack(spacing: 0) {
                    rows
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: cardRadius))
            }
        } else {
            Section {
                rows
            } header: {
                header
            }
        }
    }

    /// "DAY 1" in the trip's color with the date and stop count beside it,
    /// like a Plan My Day step header.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dayTitle)
                .font(AppFont.barlowCondensed(26, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(trip.theme.accentColor)
            Text(group.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                .font(AppFont.outfit(12, weight: .medium, relativeTo: .caption))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            if let travelTotal {
                Label("\(TravelFormat.duration(travelTotal.duration)) · \(TravelFormat.distance(travelTotal.distance))", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .textCase(nil)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Travel today: \(TravelFormat.duration(travelTotal.duration)), \(TravelFormat.distance(travelTotal.distance))")
            } else if group.activityCount > 0 {
                Text(group.activityCount == 1 ? "1 stop" : "\(group.activityCount) stops")
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .textCase(nil)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
    }

    @ViewBuilder
    private var rows: some View {
        if group.entries.isEmpty {
            Button(action: onPlanDay) {
                HStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                    Text("Nothing planned yet. Plan my day")
                        .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(trip.theme.accentColor)
                .padding(.vertical, isEmbedded ? 14 : 4)
                .padding(.horizontal, isEmbedded ? 16 : 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(CardRow(isEmbedded: isEmbedded, background: cardBackground(isTop: true, isBottom: true)))
        } else {
            let count = group.entries.count
            let marker = nowIndex
            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                // Travel from the previous activity, skipping any check-in or
                // check-out row between the two. Stays and transport never
                // start or end a leg. Drawn above the "Now" marker and divider,
                // right under the stop you're leaving, as before.
                if case .activity(let next) = entry,
                   let activity = previousActivity(before: index) {
                    if let fromCoordinate = activity.coordinate, let toCoordinate = next.coordinate {
                        TravelConnectorView(
                            isEmbedded: isEmbedded,
                            fromCoordinate: fromCoordinate,
                            toCoordinate: toCoordinate,
                            originName: activity.title,
                            nextStart: next.date,
                            destinationName: next.title,
                            accentColor: trip.theme.accentColor,
                            onEstimate: reportAndRemind("leg-\(activity.id)-\(next.id)", for: next)
                        )
                        .modifier(CardRow(isEmbedded: isEmbedded, background: cardBackground(isTop: false, isBottom: false)))
                    } else {
                        MissingPinRow(isEmbedded: isEmbedded, title: activity.coordinate == nil ? activity.title : next.title, accentColor: trip.theme.accentColor)
                            .modifier(CardRow(isEmbedded: isEmbedded, background: cardBackground(isTop: false, isBottom: false)))
                    }
                }
                if marker == index {
                    nowRow(isTop: index == 0, isBottom: false)
                }
                if isEmbedded && index > 0 && marker != index {
                    Divider().padding(.leading, ItineraryRail.contentInset)
                }
                // The marker row takes over the card's top/bottom edge when it sits there.
                let isFirst = index == 0 && marker != 0
                let isLast = index == count - 1 && marker != count
                if case .activity(let activity) = entry {
                    row(for: activity, isFirst: isFirst, isLast: isLast)
                } else {
                    staticRow(for: entry, isFirst: isFirst, isLast: isLast)
                }
            }
            if marker == count {
                nowRow(isTop: false, isBottom: true)
            }
        }
    }

    /// The activity a travel row into `entries[index]` starts from (see
    /// `TravelPlanning.legOriginIndex`).
    private func previousActivity(before index: Int) -> Activity? {
        let kinds = group.entries.map(\.legKind)
        guard let origin = TravelPlanning.legOriginIndex(before: index, in: kinds),
              case .activity(let activity) = group.entries[origin] else { return nil }
        return activity
    }

    /// Where "Now" falls among today's activities: the number that have
    /// already started, so 0 is before the first and `count` is after the last.
    /// nil on any other day, or when the trip isn't in progress.
    private var nowIndex: Int? {
        guard let now, !group.entries.isEmpty,
              Calendar.current.isDate(group.day, inSameDayAs: now) else { return nil }
        return group.entries.filter { $0.time <= now }.count
    }

    /// A transport departure or hotel check-in/out: shown for context, not
    /// opened or swiped, since it's generated from its own record.
    @ViewBuilder
    private func staticRow(for entry: ItineraryEntry, isFirst: Bool, isLast: Bool) -> some View {
        let content = ActivityRowView(
            title: entry.title,
            location: entry.subtitle,
            cost: nil,
            costCurrency: nil,
            costNote: nil,
            iconName: entry.iconName,
            time: entry.time,
            accentColor: trip.theme.accentColor,
            isFirst: isFirst,
            isLast: isLast,
            showsChevron: false
        )
        if isEmbedded {
            content.padding(.horizontal, 16)
        } else {
            content.modifier(CardRow(isEmbedded: false, background: cardBackground(isTop: isFirst, isBottom: isLast)))
        }
    }

    private func nowRow(isTop: Bool, isBottom: Bool) -> some View {
        NowMarkerRow(accentColor: trip.theme.accentColor, isTop: isTop, isBottom: isBottom)
            .padding(.horizontal, isEmbedded ? 16 : 0)
            .modifier(CardRow(isEmbedded: isEmbedded, background: cardBackground(isTop: isTop, isBottom: isBottom)))
    }

    @ViewBuilder
    private func row(for activity: Activity, isFirst: Bool, isLast: Bool) -> some View {
        let content = ActivityHoursRow(
            activity: activity,
            englishTitle: Self.englishName(in: activity.activityDescription),
            accentColor: trip.theme.accentColor,
            isFirst: isFirst,
            isLast: isLast
        )
        if isEmbedded {
            NavigationLink {
                ActivityDetailView(trip: trip, activity: activity, accentColor: trip.theme.accentColor, memberProfiles: memberProfiles)
            } label: {
                content
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        } else {
            // The row draws its own chevron, so the link is hidden behind it
            // (otherwise `List` adds a second disclosure indicator).
            ZStack {
                NavigationLink {
                    ActivityDetailView(trip: trip, activity: activity, accentColor: trip.theme.accentColor, memberProfiles: memberProfiles)
                } label: {
                    EmptyView()
                }
                .opacity(0)
                content
            }
            // No vertical insets or separators, so the connecting line runs
            // unbroken from one stop to the next.
            .modifier(CardRow(isEmbedded: false, background: cardBackground(isTop: isFirst, isBottom: isLast)))
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    delete(activity)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    /// Plan My Day saves the English name of a foreign-language place as
    /// "English: <name>" in the description; show it under the title.
    private static func englishName(in description: String) -> String? {
        let prefix = "English: "
        guard description.hasPrefix(prefix) else { return nil }
        let name = description.dropFirst(prefix.count).split(separator: "\n").first.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

    /// Mirrors `ActivityDetailView`'s delete: remote first (for synced
    /// trips), then the reminder, then the local object.
    private func delete(_ activity: Activity) {
        if trip.ownerUID != nil {
            let tripID = trip.id
            let activityID = activity.id
            Task {
                try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "activities", docID: activityID)
            }
        }
        NotificationScheduler.cancelReminder(forActivityID: activity.id)
        modelContext.delete(activity)
    }

}

/// The travel row between two activities: distance and time for the chosen
/// way of getting around, and a menu that opens the leg in Apple Maps or Google Maps.
private struct TravelConnectorView: View {
    @Environment(\.openURL) private var openURL
    var isEmbedded = false
    let fromCoordinate: CLLocationCoordinate2D
    let toCoordinate: CLLocationCoordinate2D
    /// Name of the stop you're leaving, for the steps sheet and Apple Maps.
    var originName: String = ""
    /// Start of the stop you're heading to, for the transit steps' arrive-by time.
    let nextStart: Date
    var destinationName: String = ""
    let accentColor: Color
    /// Reports the figure currently shown, so the day can add up its travel.
    var onEstimate: (TravelEstimate?) -> Void = { _ in }

    @State private var selectedMode: MKDirectionsTransportType
    /// True once the traveler taps a mode, which stops automatic fallback.
    @State private var userPickedMode = false
    // Keyed by `rawValue` rather than the mode itself — `MKDirectionsTransportType`
    // is an OptionSet without Hashable conformance.
    @State private var estimatesByMode: [UInt: TravelEstimate] = [:]
    @State private var isLoading = false
    @State private var loadFailed = false
    /// The last figure shown. It stays on screen while another mode loads, so
    /// switching modes never swaps the text for a spinner and shifts the row.
    @State private var shownEstimate: TravelEstimate?
    @State private var showingSteps = false

    private static let modes: [MKDirectionsTransportType] = [.walking, .transit, .automobile, .cycling]

    init(isEmbedded: Bool = false, fromCoordinate: CLLocationCoordinate2D, toCoordinate: CLLocationCoordinate2D, originName: String = "", nextStart: Date, destinationName: String = "", accentColor: Color, onEstimate: @escaping (TravelEstimate?) -> Void = { _ in }) {
        self.isEmbedded = isEmbedded
        self.fromCoordinate = fromCoordinate
        self.toCoordinate = toCoordinate
        self.originName = originName
        self.nextStart = nextStart
        self.destinationName = destinationName
        self.accentColor = accentColor
        self.onEstimate = onEstimate
        _selectedMode = State(initialValue: TravelPlanning.initialMode(from: fromCoordinate, to: toCoordinate))
    }

    private var currentEstimate: TravelEstimate? { estimatesByMode[selectedMode.rawValue] }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: ItineraryRail.timeWidth)
            ItineraryRailLine(accentColor: accentColor)
            VStack(alignment: .leading, spacing: 4) {
                controls
                details
            }
            .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, isEmbedded ? 16 : 0)
        .task(id: selectedMode.rawValue) {
            await loadEstimateIfNeeded()
        }
        .onChange(of: currentEstimate?.duration) {
            onEstimate(currentEstimate)
        }
        .onDisappear { onEstimate(nil) }
        .sheet(isPresented: $showingSteps) {
            TransitStepsSheet(
                fromName: originName.isEmpty ? "Previous stop" : originName,
                toName: destinationName.isEmpty ? "Next stop" : destinationName,
                fromCoordinate: fromCoordinate,
                toCoordinate: toCoordinate,
                arriveBy: nextStart,
                accentColor: accentColor
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            ForEach(Self.modes, id: \.rawValue) { mode in
                Button {
                    userPickedMode = true
                    selectedMode = mode
                } label: {
                    Image(systemName: mode.sfSymbolName)
                        .font(.caption2)
                        .padding(6)
                        .background(selectedMode == mode ? accentColor.opacity(0.2) : Color.clear)
                        .foregroundStyle(selectedMode == mode ? accentColor : .secondary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.modeName(mode))
                .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
            }

            Group {
                if let estimate = currentEstimate ?? (loadFailed ? nil : shownEstimate) {
                    Text("\(formattedDistance(estimate.distance)) · \(formattedDuration(estimate.duration))")
                        // Dimmed, not replaced, while the new mode's figure loads.
                        .opacity(currentEstimate == nil && isLoading ? 0.45 : 1)
                } else if loadFailed {
                    Text(selectedMode == .transit ? "No transit here" : "Unavailable")
                } else if isLoading {
                    // Only the very first load has nothing to show yet.
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(AppFont.outfit(12, relativeTo: .caption))
            .foregroundStyle(.secondary)
            .fixedSize()

            Spacer(minLength: 4)

            Menu {
                Button("Apple Maps", systemImage: "map", action: openInMaps)
                Button("Google Maps", systemImage: "globe", action: openInGoogleMaps)
            } label: {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.subheadline)
                    .foregroundStyle(accentColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Directions")
            .accessibilityHint("Opens this leg in Apple Maps or Google Maps")
        }
    }

    /// The transit "Steps" button; nothing for other modes.
    @ViewBuilder
    private var details: some View {
        // MapKit only has transit ETAs; Google has the lines and stops,
        // and often covers cities MapKit doesn't, so offer it even when
        // MapKit found no transit.
        if selectedMode == .transit {
            Button {
                showingSteps = true
            } label: {
                Label("Steps", systemImage: "list.bullet")
                    .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Transit steps")
            .accessibilityHint("Shows which lines and stops to take, from Google")
        }
    }

    private func loadEstimateIfNeeded() async {
        guard estimatesByMode[selectedMode.rawValue] == nil else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let estimate = try await TravelEstimateService.estimate(from: fromCoordinate, to: toCoordinate, transportType: selectedMode)
            estimatesByMode[selectedMode.rawValue] = estimate
            shownEstimate = estimate
        } catch {
            // The automatic pick had no route (usually no transit data in
            // this city): quietly move on to the next mode instead of
            // showing an error the traveler didn't ask for.
            if !userPickedMode, let next = TravelPlanning.fallbackMode(after: selectedMode) {
                selectedMode = next
            } else {
                loadFailed = true
            }
        }
    }

    private func openInMaps() {
        let source = MKMapItem(placemark: MKPlacemark(coordinate: fromCoordinate))
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: toCoordinate))
        if !originName.isEmpty { source.name = originName }
        if !destinationName.isEmpty { destination.name = destinationName }
        MKMapItem.openMaps(with: [source, destination], launchOptions: [MKLaunchOptionsDirectionsModeKey: selectedMode.mapsLaunchMode])
    }

    private func openInGoogleMaps() {
        guard let url = TravelPlanning.googleMapsURL(from: fromCoordinate, to: toCoordinate, mode: selectedMode) else { return }
        openURL(url)
    }

    private static func modeName(_ mode: MKDirectionsTransportType) -> String {
        switch mode {
        case .walking: return "Walk"
        case .transit: return "Transit"
        case .cycling: return "Bike"
        default: return "Car"
        }
    }

    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: meters)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        TravelFormat.duration(seconds)
    }
}

/// Shared duration text for travel rows and the day's travel total.
enum TravelFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "\(Int(seconds / 60)) min"
    }

    static func distance(_ meters: CLLocationDistance) -> String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: meters)
    }
}

/// Shown where a travel row would be when one of the two stops has no map
/// pin, so travel info doesn't silently go missing.
private struct MissingPinRow: View {
    var isEmbedded = false
    let title: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: ItineraryRail.timeWidth)
            ItineraryRailLine(accentColor: accentColor)
            Label("Pin \(title) on the map to see travel time", systemImage: "mappin.slash")
                .font(AppFont.outfit(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, isEmbedded ? 16 : 0)
    }
}

/// A "Now" line between the stops that have started and the ones still to
/// come: a red label and dot on the rail, with a red rule across the row.
private struct NowMarkerRow: View {
    let accentColor: Color
    /// At the card's top or bottom edge the rail line only continues one way.
    let isTop: Bool
    let isBottom: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("Now")
                .font(AppFont.outfit(12, weight: .bold, relativeTo: .caption))
                .textCase(.uppercase)
                .foregroundStyle(.red)
                .frame(width: ItineraryRail.timeWidth, alignment: .leading)
            ZStack {
                VStack(spacing: 0) {
                    Rectangle().fill(accentColor.opacity(0.35)).frame(width: 2).opacity(isTop ? 0 : 1)
                    Rectangle().fill(accentColor.opacity(0.35)).frame(width: 2).opacity(isBottom ? 0 : 1)
                }
                Circle().fill(.red).frame(width: 10, height: 10)
            }
            .frame(width: ItineraryRail.railWidth)
            .frame(maxHeight: .infinity)
            Capsule().fill(.red).frame(height: 2)
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current time")
    }
}

private struct DayGroup {
    let day: Date
    let entries: [ItineraryEntry]

    var activityCount: Int {
        entries.filter { if case .activity = $0 { return true } else { return false } }.count
    }
}

/// One line of a day: a real activity, or something shown straight from its
/// own record (a transport departure, a hotel check-in or check-out).
private enum ItineraryEntry: Identifiable {
    case activity(Activity)
    case transport(TransportSegment)
    /// The same segment again, at its arrival time.
    case arrival(TransportSegment)
    case checkIn(Accommodation)
    case checkOut(Accommodation)

    var id: String {
        switch self {
        case .activity(let activity): return "activity-\(activity.id)"
        case .transport(let segment): return "transport-\(segment.id)"
        case .arrival(let segment): return "arrival-\(segment.id)"
        case .checkIn(let stay): return "checkin-\(stay.id)"
        case .checkOut(let stay): return "checkout-\(stay.id)"
        }
    }

    /// How this row counts for travel legs between activities.
    var legKind: TravelPlanning.TimelineRowKind {
        switch self {
        case .activity: return .activity
        case .checkIn, .checkOut: return .stay
        case .transport, .arrival: return .transport
        }
    }

    var time: Date {
        switch self {
        case .activity(let activity): return activity.date
        case .transport(let segment): return segment.departureDateTime
        case .arrival(let segment): return segment.arrivalDateTime ?? segment.departureDateTime
        case .checkIn(let stay): return Self.date(stay.startDate, atTime: stay.checkInTime)
        case .checkOut(let stay): return Self.date(stay.endDate, atTime: stay.checkOutTime)
        }
    }

    var title: String {
        switch self {
        case .activity(let activity): return activity.title
        case .transport(let segment): return segment.mode.displayName
        case .arrival(let segment):
            return segment.arrivalLocation.isEmpty ? "Arrive" : "Arrive · \(segment.arrivalLocation)"
        case .checkIn(let stay): return "Check-in · \(stay.name)"
        case .checkOut(let stay): return "Check-out · \(stay.name)"
        }
    }

    var subtitle: String {
        switch self {
        case .activity(let activity):
            return activity.location
        case .transport(let segment):
            var parts: [String] = []
            let route = [segment.departureLocation, segment.arrivalLocation].filter { !$0.isEmpty }
            if !route.isEmpty { parts.append(route.joined(separator: " → ")) }
            if let arrival = segment.arrivalDateTime {
                let sameDay = Calendar.current.isDate(arrival, inSameDayAs: segment.departureDateTime)
                let format = sameDay
                    ? arrival.formatted(date: .omitted, time: .shortened)
                    : arrival.formatted(date: .abbreviated, time: .shortened)
                parts.append("Arrives \(format)")
            }
            return parts.joined(separator: " · ")
        case .arrival(let segment):
            return segment.departureLocation.isEmpty
                ? segment.mode.displayName
                : "\(segment.mode.displayName) from \(segment.departureLocation)"
        case .checkIn(let stay), .checkOut(let stay):
            return stay.location
        }
    }

    var iconName: String {
        switch self {
        case .activity(let activity): return activity.iconName
        case .transport(let segment): return segment.mode.iconName
        case .arrival(let segment): return segment.mode == .flight ? "airplane.arrival" : "mappin.and.ellipse"
        case .checkIn: return "bed.double"
        case .checkOut: return "door.left.hand.open"
        }
    }

    var orderKey: ItineraryOrder.Key {
        switch self {
        case .transport:
            return .init(time: time, rank: .departure)
        case .arrival(let segment):
            // A leg that lands the minute it leaves keeps its arrival after its departure.
            let instant = ItineraryOrder.minute(time) == ItineraryOrder.minute(segment.departureDateTime)
            return .init(time: time, rank: instant ? .instantArrival : .arrival)
        case .activity, .checkIn, .checkOut:
            return .init(time: time, rank: .other)
        }
    }

    /// Combines a day with an "HH:mm" string, as the models store times.
    private static func date(_ day: Date, atTime time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return day }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
    }
}

/// How a day's lines are ordered: by minute, and within the same minute a
/// transport arrival first (you land, then do things), then activities and
/// hotel times, then a departure (you do things, then leave). So a leg's
/// departure and arrival stay side by side unless something is planned
/// strictly between them.
enum ItineraryOrder {
    enum Rank: Int {
        case arrival, other, departure, instantArrival
    }

    struct Key {
        let time: Date
        let rank: Rank
    }

    static func precedes(_ a: Key, _ b: Key) -> Bool {
        let minuteA = minute(a.time), minuteB = minute(b.time)
        if minuteA != minuteB { return minuteA < minuteB }
        return a.rank.rawValue < b.rank.rawValue
    }

    /// Times are picked to the minute; leftover seconds shouldn't decide order.
    static func minute(_ date: Date) -> Int {
        Int((date.timeIntervalSinceReferenceDate / 60).rounded(.down))
    }
}

/// Row chrome for the full-screen list, where a day's card is drawn row by row:
/// our own background, inset to the card's edges, and no separators. Inline rows
/// sit inside a card that is already drawn, so they need nothing.
private struct CardRow<Background: View>: ViewModifier {
    let isEmbedded: Bool
    let background: Background

    func body(content: Content) -> some View {
        if isEmbedded {
            content
        } else {
            content
                .listRowBackground(background)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: 32, bottom: 0, trailing: 32))
        }
    }
}

/// An activity's itinerary row that also checks Google's opening hours for
/// its time, when the activity has a place ID, and says so if it's closed then.
private struct ActivityHoursRow: View {
    let activity: Activity
    let englishTitle: String?
    let accentColor: Color
    let isFirst: Bool
    let isLast: Bool

    @State private var isClosed = false

    var body: some View {
        ActivityRowView(
            title: activity.title,
            location: activity.location,
            cost: activity.cost,
            costCurrency: activity.costCurrency,
            costNote: activity.costNote,
            iconName: activity.iconName,
            time: activity.date,
            englishTitle: englishTitle,
            accentColor: accentColor,
            isFirst: isFirst,
            isLast: isLast,
            notice: isClosed ? "Closed at this time" : nil,
            addedByClaude: activity.isFromClaude
        )
        .task(id: "\(activity.placeID ?? "")|\(activity.date.timeIntervalSince1970)") {
            guard let placeID = activity.placeID, !placeID.isEmpty else {
                isClosed = false
                return
            }
            let hours = await PlaceHoursStore.hours(for: placeID)
            isClosed = hours?.isOpen(at: activity.date) == false
        }
    }
}
