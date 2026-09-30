import SwiftUI
import SwiftData

struct DayNoteListView: View {
    let trip: Trip

    /// Live query scoped to this trip rather than a `trip.dayNotes`
    /// traversal — see `ItineraryTimelineView`'s equivalent property for why.
    @Query private var dayNotes: [DayNote]

    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var editingNote: DayNote?

    init(trip: Trip) {
        self.trip = trip
        let tripID = trip.id
        _dayNotes = Query(filter: #Predicate<DayNote> { $0.trip?.id == tripID })
    }

    private var sorted: [DayNote] {
        dayNotes.sorted { $0.day < $1.day }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                EmptyStateView(
                    iconName: "note.text",
                    title: "No Notes Yet",
                    message: "Jot down reminders or plans for specific days.",
                    actionTitle: "Add Note",
                    action: { isAdding = true }
                )
            } else {
                List {
                    ForEach(sorted) { note in
                        Button {
                            editingNote = note
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.day.formatted(date: .abbreviated, time: .omitted))
                                    .font(AppFont.outfit(12, relativeTo: .caption))
                                    .foregroundStyle(.secondary)
                                Text(note.title)
                                    .font(AppFont.outfit(17, weight: .semibold, relativeTo: .body))
                                if !note.content.isEmpty {
                                    Text(note.content)
                                        .font(AppFont.outfit(12, relativeTo: .caption))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Day Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Add Note", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            DayNoteEditSheet(trip: trip)
        }
        .sheet(item: $editingNote) { note in
            DayNoteEditSheet(trip: trip, editingNote: note)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let note = sorted[index]
            if trip.ownerUID != nil {
                let tripID = trip.id
                let noteID = note.id
                Task {
                    try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "dayNotes", docID: noteID)
                }
            }
            modelContext.delete(note)
        }
    }
}
