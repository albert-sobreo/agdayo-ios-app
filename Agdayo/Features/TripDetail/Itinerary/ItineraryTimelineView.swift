import SwiftUI
import MapKit
import CoreLocation

struct ItineraryTimelineView: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    @State private var isAddingActivity = false
    @State private var forecastsByDay: [Date: DailyForecastSummary] = [:]

    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: trip.activities) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { day in
            let dayActivities = (grouped[day] ?? []).sorted { $0.date < $1.date }
            let buckets = TimeOfDayBucket.allCases.compactMap { bucket -> BucketGroup? in
                let matches = dayActivities.filter { bucket.contains(hour: calendar.component(.hour, from: $0.date)) }
                return matches.isEmpty ? nil : BucketGroup(bucket: bucket, activities: matches)
            }
            return DayGroup(day: day, buckets: buckets)
        }
    }

    var body: some View {
        ScrollView {
            if trip.activities.isEmpty {
                EmptyStateView(
                    iconName: "note.text",
                    title: "No Activities Yet",
                    message: "Add your first stop to start building the itinerary.",
                    actionTitle: "Add Activity"
                ) {
                    isAddingActivity = true
                }
                .padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(dayGroups.enumerated()), id: \.element.day) { index, group in
                        DaySection(dayIndex: index + 1, group: group, trip: trip, forecast: forecastsByDay[group.day], memberProfiles: memberProfiles)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Itinerary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingActivity = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Activity")
            }
        }
        .sheet(isPresented: $isAddingActivity) {
            ActivityEditSheet(trip: trip, memberProfiles: memberProfiles)
        }
        .task {
            await loadForecasts()
        }
    }

    /// Fails soft — no WeatherKit capability yet, no network, or the trip's
    /// dates simply fall outside WeatherKit's ~10-day forecast window all
    /// just mean no chips show, not an error.
    private func loadForecasts() async {
        guard let coordinate = trip.coordinate else { return }
        guard let daily = try? await WeatherForecastService.dailyForecast(for: coordinate) else { return }
        let calendar = Calendar.current
        forecastsByDay = Dictionary(daily.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })
    }
}

private struct DaySection: View {
    let dayIndex: Int
    let group: DayGroup
    let trip: Trip
    var forecast: DailyForecastSummary?
    var memberProfiles: [AppUserProfile] = []

    /// Flattened across bucket boundaries so travel time is computed between
    /// actual consecutive stops (e.g. last Morning stop → first Noon stop),
    /// not reset at each time-of-day divider.
    private var orderedActivities: [Activity] {
        group.buckets.flatMap(\.activities)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Day \(dayIndex) · \(group.day.formatted(date: .abbreviated, time: .omitted))")
                    .font(AppFont.outfit(20, weight: .semibold, relativeTo: .title3))
                if let forecast {
                    Spacer()
                    WeatherChip(forecast: forecast)
                }
            }

            ForEach(group.buckets) { bucket in
                TimeOfDayDivider(label: bucket.bucket.label)
                ForEach(Array(bucket.activities.enumerated()), id: \.element.id) { index, activity in
                    NavigationLink {
                        ActivityDetailView(trip: trip, activity: activity, accentColor: trip.theme.accentColor, memberProfiles: memberProfiles)
                    } label: {
                        ActivityRowView(
                            title: activity.title,
                            location: activity.location,
                            cost: activity.cost,
                            costCurrency: activity.costCurrency,
                            costNote: activity.costNote,
                            iconName: activity.iconName,
                            time: activity.date,
                            isLast: index == bucket.activities.count - 1
                        )
                    }
                    .buttonStyle(.plain)

                    if let next = nextActivity(after: activity),
                       let fromCoordinate = activity.coordinate,
                       let toCoordinate = next.coordinate {
                        TravelConnectorView(fromCoordinate: fromCoordinate, toCoordinate: toCoordinate, accentColor: trip.theme.accentColor)
                    }
                }
            }
        }
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

private struct WeatherChip: View {
    let forecast: DailyForecastSummary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: forecast.symbolName)
                .symbolRenderingMode(.multicolor)
            Text(forecast.highTemperature.formatted(.measurement(width: .narrow, usage: .weather, hidesScaleName: true, numberFormatStyle: .number.precision(.fractionLength(0)))))
            Text("/")
                .foregroundStyle(.secondary)
            Text(forecast.lowTemperature.formatted(.measurement(width: .narrow, usage: .weather, hidesScaleName: true, numberFormatStyle: .number.precision(.fractionLength(0)))))
                .foregroundStyle(.secondary)
        }
        .font(AppFont.outfit(12, weight: .medium, relativeTo: .caption))
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
