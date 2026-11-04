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

    init(trip: Trip, memberProfiles: [AppUserProfile] = [], isEmbedded: Bool = false) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        self.isEmbedded = isEmbedded
        let tripID = trip.id
        _activities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID }, sort: \Activity.date)
        _transportSegments = Query(filter: #Predicate<TransportSegment> { $0.trip?.id == tripID })
        _accommodations = Query(filter: #Predicate<Accommodation> { $0.trip?.id == tripID })
    }

    /// Activities, transport departures and hotel check-in/out, all in one list.
    private var allEntries: [ItineraryEntry] {
        activities.map(ItineraryEntry.activity)
            + transportSegments.map(ItineraryEntry.transport)
            + accommodations.flatMap { [ItineraryEntry.checkIn($0), ItineraryEntry.checkOut($0)] }
    }

    /// Every trip day is listed; empty days get a "Plan my day" row.
    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: allEntries) { calendar.startOfDay(for: $0.time) }
        let days = Set(trip.calendarDays).union(grouped.keys)
        return days.sorted().map { day in
            DayGroup(day: day, entries: (grouped[day] ?? []).sorted { $0.time < $1.time })
        }
    }

    /// "Day N" counts from the trip's first day, so something booked outside the
    /// trip's dates (a flight the evening before) is labelled as such instead
    /// of becoming "Day 1" and shifting every real day along.
    private func dayTitle(for day: Date) -> String {
        let calendar = Calendar.current
        let tripDays = trip.calendarDays.map { calendar.startOfDay(for: $0) }.sorted()
        if let index = tripDays.firstIndex(of: day) { return "Day \(index + 1)" }
        guard let first = tripDays.first else { return "Day 1" }
        return day < first ? "Before trip" : "After trip"
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
                            stays: accommodations,
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
                List {
                    ForEach(Array(dayGroups.enumerated()), id: \.element.day) { index, group in
                        DaySection(
                            dayTitle: dayTitle(for: group.day),
                            group: group,
                            trip: trip,
                            memberProfiles: memberProfiles,
                            stays: accommodations,
                            now: nowMarker,
                            isEmbedded: false,
                            onPlanDay: { startPlanning(day: group.day) }
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(BrandPalette.canvas.ignoresSafeArea())
            }
        }
    }

    /// Stays saved before stays had map pins only have an address or name.
    /// Look each one up once so travel from the stay works without the
    /// traveler re-entering it. A wrong match can be fixed by picking the
    /// right result in the stay's edit sheet.
    private func pinStaysWithoutCoordinates() async {
        for stay in accommodations where stay.coordinate == nil {
            let query = stay.location.isEmpty ? stay.name : stay.location
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
                  let found = await DayBaseResolver.place(named: query, near: trip.coordinate),
                  !found.isBroad else { continue }
            stay.latitude = found.coordinate.latitude
            stay.longitude = found.coordinate.longitude
            if trip.ownerUID != nil {
                let tripID = trip.id
                let stayID = stay.id
                let dto = stay.dto
                Task {
                    try? await FirestoreCollectionSync.push(tripID: tripID, collection: "accommodations", docID: stayID, data: dto)
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
            await pinStaysWithoutCoordinates()
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
    /// Every stay on the trip; the one covering this day is where its travel starts.
    var stays: [Accommodation] = []
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

    /// Where this day starts: the pinned stay covering it.
    private var stay: Accommodation? { TravelPlanning.stay(for: group.day, in: stays) }

    /// The day's first stop with a map pin, which gets a travel row from the stay.
    private var firstLocatedActivityID: UUID? {
        for entry in group.entries {
            if case .activity(let activity) = entry, activity.coordinate != nil { return activity.id }
        }
        return nil
    }

    private var travelTotal: (duration: TimeInterval, distance: CLLocationDistance)? {
        guard !legEstimates.isEmpty else { return nil }
        let duration = legEstimates.values.reduce(TimeInterval(0)) { $0 + $1.duration }
        let distance = legEstimates.values.reduce(CLLocationDistance(0)) { $0 + $1.distance }
        return (duration, distance)
    }

    private func report(_ key: String) -> (TravelEstimate?) -> Void {
        { estimate in legEstimates[key] = estimate }
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
                if marker == index {
                    nowRow(isTop: index == 0, isBottom: false)
                }
                if isEmbedded && index > 0 && marker != index {
                    Divider().padding(.leading, ItineraryRail.contentInset)
                }
                // The marker row takes over the card's top/bottom edge when it sits there.
                let isFirst = index == 0 && marker != 0
                let isLast = index == count - 1 && marker != count
                // Travel from the stay to the day's first pinned stop.
                if case .activity(let activity) = entry,
                   activity.id == firstLocatedActivityID,
                   let stay, let stayCoordinate = stay.coordinate,
                   let toCoordinate = activity.coordinate,
                   !Self.isSamePlace(stayCoordinate, toCoordinate) {
                    TravelConnectorView(
                        isEmbedded: isEmbedded,
                        fromCoordinate: stayCoordinate,
                        toCoordinate: toCoordinate,
                        fromLabel: "From \(stay.name)",
                        nextStart: activity.date,
                        destinationName: activity.title,
                        accentColor: trip.theme.accentColor,
                        onEstimate: report("stay-\(activity.id)")
                    )
                    .modifier(CardRow(isEmbedded: isEmbedded, background: cardBackground(isTop: false, isBottom: false)))
                }
                if case .activity(let activity) = entry {
                    row(for: activity, isFirst: isFirst, isLast: isLast)
                } else {
                    staticRow(for: entry, isFirst: isFirst, isLast: isLast)
                }
                // Travel time is only estimated between two consecutive activities.
                if case .activity(let activity) = entry,
                   index + 1 < count,
                   case .activity(let next) = group.entries[index + 1] {
                    if let fromCoordinate = activity.coordinate, let toCoordinate = next.coordinate {
                        TravelConnectorView(
                            isEmbedded: isEmbedded,
                            fromCoordinate: fromCoordinate,
                            toCoordinate: toCoordinate,
                            previousStart: activity.date,
                            nextStart: next.date,
                            destinationName: next.title,
                            accentColor: trip.theme.accentColor,
                            onEstimate: report("leg-\(activity.id)-\(next.id)")
                        )
                        .modifier(CardRow(isEmbedded: isEmbedded, background: cardBackground(isTop: false, isBottom: false)))
                    } else {
                        MissingPinRow(isEmbedded: isEmbedded, title: activity.coordinate == nil ? activity.title : next.title, accentColor: trip.theme.accentColor)
                            .modifier(CardRow(isEmbedded: isEmbedded, background: cardBackground(isTop: false, isBottom: false)))
                    }
                }
            }
            if marker == count {
                nowRow(isTop: false, isBottom: true)
            }
        }
    }

    /// Within about 50 m: the stop is the stay itself, so no travel row.
    private static func isSamePlace(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)) < 50
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
        let content = ActivityRowView(
            title: activity.title,
            location: activity.location,
            cost: activity.cost,
            costCurrency: activity.costCurrency,
            costNote: activity.costNote,
            iconName: activity.iconName,
            time: activity.date,
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

/// The travel row between two stops (or from your stay to the day's first
/// stop): distance and time for the chosen way of getting around, when to
/// leave, a warning when the next stop starts before you could get there,
/// and a menu that opens the leg in Apple Maps or Google Maps.
private struct TravelConnectorView: View {
    @Environment(\.openURL) private var openURL
    var isEmbedded = false
    let fromCoordinate: CLLocationCoordinate2D
    let toCoordinate: CLLocationCoordinate2D
    /// "From Hotel Name" on the first row of a day; nil between stops.
    var fromLabel: String?
    /// Start of the stop you're leaving, for the tight-gap check. nil when
    /// leaving your stay, which has no start time.
    var previousStart: Date?
    /// Start of the stop you're heading to, for the leave-by time.
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

    private static let modes: [MKDirectionsTransportType] = [.walking, .transit, .automobile, .cycling]

    init(isEmbedded: Bool = false, fromCoordinate: CLLocationCoordinate2D, toCoordinate: CLLocationCoordinate2D, fromLabel: String? = nil, previousStart: Date? = nil, nextStart: Date, destinationName: String = "", accentColor: Color, onEstimate: @escaping (TravelEstimate?) -> Void = { _ in }) {
        self.isEmbedded = isEmbedded
        self.fromCoordinate = fromCoordinate
        self.toCoordinate = toCoordinate
        self.fromLabel = fromLabel
        self.previousStart = previousStart
        self.nextStart = nextStart
        self.destinationName = destinationName
        self.accentColor = accentColor
        self.onEstimate = onEstimate
        _selectedMode = State(initialValue: TravelPlanning.initialMode(from: fromCoordinate, to: toCoordinate))
    }

    private var currentEstimate: TravelEstimate? { estimatesByMode[selectedMode.rawValue] }

    private var isTight: Bool {
        guard let previousStart, let currentEstimate else { return false }
        return TravelPlanning.isTight(previousStart: previousStart, nextStart: nextStart, travelTime: currentEstimate.duration)
    }

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: ItineraryRail.timeWidth)
            ItineraryRailLine(accentColor: accentColor)
            VStack(alignment: .leading, spacing: 4) {
                if let fromLabel {
                    Label(fromLabel, systemImage: "bed.double")
                        .font(AppFont.outfit(12, weight: .medium, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

    @ViewBuilder
    private var details: some View {
        if let currentEstimate {
            if isTight, let previousStart {
                let gap = nextStart.timeIntervalSince(previousStart)
                Label("Tight: \(formattedDuration(currentEstimate.duration)) travel, \(formattedDuration(max(gap, 0))) between stops", systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(.orange)
            } else {
                Text("Leave by \(TravelPlanning.leaveBy(arrival: nextStart, travelTime: currentEstimate.duration).formatted(date: .omitted, time: .shortened))")
                    .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                    .foregroundStyle(accentColor)
            }
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
        if let fromLabel { source.name = fromLabel.replacingOccurrences(of: "From ", with: "") }
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
    case checkIn(Accommodation)
    case checkOut(Accommodation)

    var id: String {
        switch self {
        case .activity(let activity): return "activity-\(activity.id)"
        case .transport(let segment): return "transport-\(segment.id)"
        case .checkIn(let stay): return "checkin-\(stay.id)"
        case .checkOut(let stay): return "checkout-\(stay.id)"
        }
    }

    var time: Date {
        switch self {
        case .activity(let activity): return activity.date
        case .transport(let segment): return segment.departureDateTime
        case .checkIn(let stay): return Self.date(stay.startDate, atTime: stay.checkInTime)
        case .checkOut(let stay): return Self.date(stay.endDate, atTime: stay.checkOutTime)
        }
    }

    var title: String {
        switch self {
        case .activity(let activity): return activity.title
        case .transport(let segment): return segment.mode.displayName
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
        case .checkIn(let stay), .checkOut(let stay):
            return stay.location
        }
    }

    var iconName: String {
        switch self {
        case .activity(let activity): return activity.iconName
        case .transport(let segment): return segment.mode.iconName
        case .checkIn: return "bed.double"
        case .checkOut: return "door.left.hand.open"
        }
    }

    /// Combines a day with an "HH:mm" string, as the models store times.
    private static func date(_ day: Date, atTime time: String) -> Date {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return day }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
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
