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

    @State private var isAddingActivity = false
    @State private var isGeneratingWithAI = false
    /// Non-nil while the Plan My Day sheet is up; a nil `day` means "pick one for me".
    @State private var planRequest: PlanRequest?

    private struct PlanRequest: Identifiable {
        let id = UUID()
        let day: Date?
    }

    init(trip: Trip, memberProfiles: [AppUserProfile] = [], isEmbedded: Bool = false) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        self.isEmbedded = isEmbedded
        let tripID = trip.id
        _activities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID }, sort: \Activity.date)
    }

    /// Every trip day is listed; empty days get a "Plan my day" row.
    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: activities) { calendar.startOfDay(for: $0.date) }
        let days = Set(trip.calendarDays).union(grouped.keys)
        return days.sorted().map { day in
            let dayActivities = (grouped[day] ?? []).sorted { $0.date < $1.date }
            let buckets = TimeOfDayBucket.allCases.compactMap { bucket -> BucketGroup? in
                let matches = dayActivities.filter { bucket.contains(hour: calendar.component(.hour, from: $0.date)) }
                return matches.isEmpty ? nil : BucketGroup(bucket: bucket, activities: matches)
            }
            return DayGroup(day: day, buckets: buckets)
        }
    }

    @ViewBuilder
    private var content: some View {
        if activities.isEmpty {
            ScrollView {
                EmptyStateView(
                    iconName: "note.text",
                    title: "No Activities Yet",
                    message: "Add your first stop to start building the itinerary.",
                    actionTitle: "Add Activity",
                    action: { isAddingActivity = true },
                    secondaryActionTitle: "Plan My Day",
                    secondaryAction: { planRequest = PlanRequest(day: nil) }
                )
                .padding(.top, 60)
            }
        } else {
            if isEmbedded {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(dayGroups.enumerated()), id: \.element.day) { index, group in
                        DaySection(
                            dayIndex: index + 1,
                            group: group,
                            trip: trip,
                            memberProfiles: memberProfiles,
                            onPlanDay: { planRequest = PlanRequest(day: group.day) }
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
                            dayIndex: index + 1,
                            group: group,
                            trip: trip,
                            memberProfiles: memberProfiles,
                            onPlanDay: { planRequest = PlanRequest(day: group.day) }
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
                    Button("Plan My Day", systemImage: "wand.and.stars") { planRequest = PlanRequest(day: nil) }
                    if AIAvailability.isItineraryGenerationAvailable {
                        Button("Ask AI", systemImage: "sparkles") { isGeneratingWithAI = true }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add to Itinerary")
            }
        }
        .sheet(item: $planRequest) { request in
            PlanMyDaySheet(trip: trip, initialDay: request.day)
        }
        .sheet(isPresented: $isAddingActivity) {
            ActivityEditSheet(trip: trip, memberProfiles: memberProfiles)
        }
        .sheet(isPresented: $isGeneratingWithAI) {
            if #available(iOS 26.0, *) {
                AIItineraryReviewSheet(trip: trip, memberProfiles: memberProfiles)
            }
        }
    }
}

private struct DaySection: View {
    let dayIndex: Int
    let group: DayGroup
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []
    var onPlanDay: () -> Void = {}

    @Environment(\.modelContext) private var modelContext

    /// Flattened across bucket boundaries so travel time is computed between
    /// actual consecutive stops (e.g. last Morning stop → first Noon stop),
    /// not reset at each time-of-day divider.
    private var orderedActivities: [Activity] {
        group.buckets.flatMap(\.activities)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Day \(dayIndex)")
                .font(AppFont.barlowCondensed(36, weight: .regular))
                .textCase(.uppercase)
            Text(group.day.formatted(
                .dateTime
                    .weekday(.abbreviated)
                    .month(.abbreviated)
                    .day()
            ))
            .font(AppFont.barlowCondensed(16, weight: .regular))
            .textCase(.uppercase)
            .tracking(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowModifiers(top: 14, bottom: 6)

        if group.buckets.isEmpty {
            Button(action: onPlanDay) {
                Label("Nothing planned yet. Plan my day", systemImage: "wand.and.stars")
                    .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .foregroundStyle(trip.theme.accentColor)
                    .background(trip.theme.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .listRowModifiers()
        }

        ForEach(group.buckets) { bucket in
            TimeOfDayDivider(label: bucket.bucket.label)
                .listRowModifiers()

            ForEach(bucket.activities, id: \.id) { activity in
                // Hidden `NavigationLink` so `List` doesn't append its
                // disclosure chevron (same trick as the trips list).
                ZStack {
                    NavigationLink {
                        ActivityDetailView(trip: trip, activity: activity, accentColor: trip.theme.accentColor, memberProfiles: memberProfiles)
                    } label: {
                        EmptyView()
                    }
                    .opacity(0)

                    ActivityRowView(
                        title: activity.title,
                        location: activity.location,
                        cost: activity.cost,
                        costCurrency: activity.costCurrency,
                        costNote: activity.costNote,
                        iconName: activity.iconName,
                        time: activity.date,
                        // Whether there's a next activity *that day*, not
                        // just in this time-of-day bucket — otherwise the
                        // connecting line stopped short at every bucket
                        // boundary.
                        isLast: nextActivity(after: activity) == nil,
                        englishTitle: Self.englishName(in: activity.activityDescription)
                    )
                }
                .listRowModifiers()
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        delete(activity)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }

                if let next = nextActivity(after: activity),
                   let fromCoordinate = activity.coordinate,
                   let toCoordinate = next.coordinate {
                    TravelConnectorView(fromCoordinate: fromCoordinate, toCoordinate: toCoordinate, accentColor: trip.theme.accentColor)
                        .listRowModifiers(top: 0, bottom: 0)
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

    private func nextActivity(after activity: Activity) -> Activity? {
        guard let index = orderedActivities.firstIndex(where: { $0.id == activity.id }) else { return nil }
        let nextIndex = index + 1
        return nextIndex < orderedActivities.count ? orderedActivities[nextIndex] : nil
    }
}

private struct TravelConnectorView: View {
    let fromCoordinate: CLLocationCoordinate2D
    let toCoordinate: CLLocationCoordinate2D
    let accentColor: Color

    @State private var selectedMode: MKDirectionsTransportType = .automobile
    // Keyed by `rawValue` rather than the mode itself — `MKDirectionsTransportType`
    // is an OptionSet without Hashable conformance.
    @State private var estimatesByMode: [UInt: TravelEstimate] = [:]
    @State private var isLoading = false
    @State private var loadFailed = false

    private static let modes: [MKDirectionsTransportType] = [.automobile, .walking, .transit, .cycling]

    private var currentEstimate: TravelEstimate? { estimatesByMode[selectedMode.rawValue] }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.modes, id: \.rawValue) { mode in
                Button {
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
            }

            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if let estimate = currentEstimate {
                    Text("\(formattedDistance(estimate.distance)) · \(formattedDuration(estimate.duration))")
                } else if loadFailed {
                    Text("Unavailable")
                }
            }
            .font(AppFont.outfit(12, relativeTo: .caption))
            .foregroundStyle(.secondary)
        }
        .padding(.leading, 34)
        .padding(.vertical, 2)
        .task(id: selectedMode.rawValue) {
            await loadEstimateIfNeeded()
        }
    }

    private func loadEstimateIfNeeded() async {
        guard estimatesByMode[selectedMode.rawValue] == nil else { return }
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            estimatesByMode[selectedMode.rawValue] = try await TravelEstimateService.estimate(from: fromCoordinate, to: toCoordinate, transportType: selectedMode)
        } catch {
            loadFailed = true
        }
    }

    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: meters)
    }

    private func formattedDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? "\(Int(seconds / 60)) min"
    }
}

private struct TimeOfDayDivider: View {
    let label: String

    var body: some View {
        ZStack {
            Divider()
            Text(label)
                .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 8)
                .background(Color(.systemBackground))
        }
        .padding(.vertical, 4)
    }
}

private struct DayGroup {
    let day: Date
    let buckets: [BucketGroup]
}

private struct BucketGroup: Identifiable {
    let bucket: TimeOfDayBucket
    let activities: [Activity]
    var id: String { bucket.label }
}

private enum TimeOfDayBucket: CaseIterable {
    case morning, noon, afternoon, evening

    var label: String {
        switch self {
        case .morning: return "Morning"
        case .noon: return "Noon"
        case .afternoon: return "Afternoon"
        case .evening: return "Evening"
        }
    }

    func contains(hour: Int) -> Bool {
        switch self {
        case .morning: return hour < 12
        case .noon: return hour == 12
        case .afternoon: return hour > 12 && hour < 18
        case .evening: return hour >= 18
        }
    }
}

private extension View {
    /// Strips `List`'s chrome so rows look like the old stacked layout.
    func listRowModifiers(top: CGFloat = 6, bottom: CGFloat = 6) -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
    }
}
