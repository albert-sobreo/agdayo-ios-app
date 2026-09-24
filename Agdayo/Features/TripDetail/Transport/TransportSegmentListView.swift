import SwiftUI
import SwiftData

struct TransportSegmentListView: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var editingSegment: TransportSegment?

    private var sorted: [TransportSegment] {
        trip.transportSegments.sorted { $0.departureDate < $1.departureDate }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                EmptyStateView(
                    iconName: "airplane",
                    title: "No Transport Yet",
                    message: "Add flights, buses, or other ways you'll get around.",
                    actionTitle: "Add Transport",
                    action: { isAdding = true }
                )
            } else {
                List {
                    ForEach(sorted) { segment in
                        Button {
                            editingSegment = segment
                        } label: {
                            TransportSegmentRow(segment: segment, accentColor: trip.theme.accentColor)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await toggleCalendar(for: segment) }
                            } label: {
                                Label(
                                    segment.calendarEventID == nil ? "Add to Calendar" : "Remove from Calendar",
                                    systemImage: segment.calendarEventID == nil ? "calendar.badge.plus" : "calendar.badge.minus"
                                )
                            }
                            .tint(trip.theme.accentColor)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Transport")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Add Transport", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            TransportSegmentEditSheet(trip: trip, memberProfiles: memberProfiles)
        }
        .sheet(item: $editingSegment) { segment in
            TransportSegmentEditSheet(trip: trip, editingSegment: segment, memberProfiles: memberProfiles)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let segment = sorted[index]
            if trip.ownerUID != nil {
                let tripID = trip.id
                let segmentID = segment.id
                Task {
                    try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "transportSegments", docID: segmentID)
                }
            }
            NotificationScheduler.cancelReminder(forTransportID: segment.id)
            modelContext.delete(segment)
        }
    }

    private func toggleCalendar(for segment: TransportSegment) async {
        if let eventID = segment.calendarEventID {
            await CalendarExportService.removeEvent(identifier: eventID)
            segment.calendarEventID = nil
        } else {
            segment.calendarEventID = await CalendarExportService.addEvent(for: segment)
        }
    }
}

private struct TransportSegmentRow: View {
    let segment: TransportSegment
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: segment.mode.iconName)
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(segment.departureLocation) → \(segment.arrivalLocation)")
                    .font(AppFont.outfit(17, weight: .semibold, relativeTo: .body))
                Text("\(segment.departureDate.formatted(date: .abbreviated, time: .omitted)) · \(segment.departureTime)")
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PillTag(text: segment.mode.displayName, background: accentColor.opacity(0.15), foreground: accentColor)
        }
        .padding(.vertical, 6)
    }
}
