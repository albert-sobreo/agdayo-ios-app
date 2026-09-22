import SwiftUI
import SwiftData

struct TripDetailView: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isShowingMap = false
    @State private var isShowingSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TripHeaderView(
                    name: trip.name,
                    location: trip.location,
                    startDate: trip.startDate,
                    endDate: trip.endDate,
                    theme: trip.theme,
                    status: trip.status,
                    planningProgress: trip.planningProgress,
                    onViewMap: { isShowingMap = true },
                    onSettings: { isShowingSettings = true }
                )

                TripSectionsRow(
                    accentColor: trip.theme.accentColor,
                    activityCount: trip.activities.count,
                    accommodationCount: trip.accommodations.count,
                    budgetedTotal: trip.budgetedTotal,
                    overallBudget: trip.overallBudget,
                    currency: trip.currency,
                    taskCount: trip.preparationTasks.count,
                    transportCount: trip.transportSegments.count,
                    noteCount: trip.dayNotes.count
                )
                .padding(.horizontal)

                UpcomingActivitiesPreview(trip: trip)
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: TripSectionRoute.self) { route in
            destination(for: route)
        }
        .sheet(isPresented: $isShowingMap) {
            NavigationStack {
                TripMapView(trip: trip)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            TripSettingsView(trip: trip, onDeleted: deleteTrip)
        }
    }

    @ViewBuilder
    private func destination(for route: TripSectionRoute) -> some View {
        switch route {
        case .itinerary:
            ItineraryTimelineView(trip: trip)
        case .accommodations:
            AccommodationListView(trip: trip)
        case .budget:
            BudgetOverviewView(trip: trip)
        case .preparation:
            PreparationChecklistView(trip: trip)
        case .transport:
            TransportSegmentListView(trip: trip)
        case .notes:
            DayNoteListView(trip: trip)
        }
    }

    private func deleteTrip() {
        modelContext.delete(trip)
        isShowingSettings = false
        dismiss()
    }
}

private struct UpcomingActivitiesPreview: View {
    let trip: Trip

    private var upcoming: [Activity] {
        trip.activities.sorted { $0.date < $1.date }.prefix(3).map { $0 }
    }

    var body: some View {
        SectionCard(title: "Upcoming Activities") {
            if upcoming.isEmpty {
                Text("No activities yet. Add one from the Itinerary section.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(upcoming) { activity in
                        UpcomingActivityRow(title: activity.title, location: activity.location, date: activity.date, iconName: activity.iconName)
                    }
                }
            }
        }
    }
}

private struct UpcomingActivityRow: View {
    let title: String
    let location: String
    let date: Date
    let iconName: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(date, format: .dateTime.month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
