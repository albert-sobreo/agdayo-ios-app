import SwiftUI
import SwiftData

struct AccommodationListView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var editingAccommodation: Accommodation?

    private var sorted: [Accommodation] {
        trip.accommodations.sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                EmptyStateView(
                    iconName: "bed.double",
                    title: "No Accommodations Yet",
                    message: "Add where you're staying during this trip.",
                    actionTitle: "Add Accommodation"
                ) {
                    isAdding = true
                }
            } else {
                List {
                    ForEach(sorted) { accommodation in
                        Button {
                            editingAccommodation = accommodation
                        } label: {
                            AccommodationRow(accommodation: accommodation, accentColor: trip.theme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Accommodations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Add Accommodation", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            AccommodationEditSheet(trip: trip)
        }
        .sheet(item: $editingAccommodation) { accommodation in
            AccommodationEditSheet(trip: trip, editingAccommodation: accommodation)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let accommodation = sorted[index]
            if trip.ownerUID != nil {
                let tripID = trip.id
                let accommodationID = accommodation.id
                Task {
                    try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "accommodations", docID: accommodationID)
                }
            }
            modelContext.delete(accommodation)
        }
    }
}

private struct AccommodationRow: View {
    let accommodation: Accommodation
    let accentColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(accommodation.name)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Text("\(accommodation.location) · \(accommodation.numberOfRooms) room(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(dateRangeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PillTag(text: accommodation.type.displayName, background: accentColor.opacity(0.15), foreground: accentColor)
        }
        .padding(.vertical, 6)
    }

    private var dateRangeText: String {
        let formatter = Date.FormatStyle().month(.abbreviated).day()
        return "\(accommodation.startDate.formatted(formatter)) – \(accommodation.endDate.formatted(formatter))"
    }
}
