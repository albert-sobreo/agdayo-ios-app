import SwiftUI

struct ItineraryTimelineView: View {
    let trip: Trip

    @State private var isAddingActivity = false
    @State private var isGeneratingWithAI = false

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
                        DaySection(dayIndex: index + 1, group: group, trip: trip)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Itinerary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Manually", systemImage: "plus") { isAddingActivity = true }
                    Button("Generate with AI", systemImage: "sparkles") { isGeneratingWithAI = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Activity")
            }
        }
        .sheet(isPresented: $isAddingActivity) {
            ActivityEditSheet(trip: trip)
        }
        .sheet(isPresented: $isGeneratingWithAI) {
            AIGenerateMoreActivitiesView(trip: trip)
        }
    }
}

private struct DaySection: View {
    let dayIndex: Int
    let group: DayGroup
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Day \(dayIndex) · \(group.day.formatted(date: .abbreviated, time: .omitted))")
                .font(.system(.title3, design: .rounded).weight(.semibold))

            ForEach(group.buckets) { bucket in
                TimeOfDayDivider(label: bucket.bucket.label)
                ForEach(Array(bucket.activities.enumerated()), id: \.element.id) { index, activity in
                    NavigationLink {
                        ActivityDetailView(trip: trip, activity: activity, accentColor: trip.theme.accentColor)
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
                }
            }
        }
    }
}

private struct TimeOfDayDivider: View {
    let label: String

    var body: some View {
        ZStack {
            Divider()
            Text(label)
                .font(.caption.weight(.semibold))
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
