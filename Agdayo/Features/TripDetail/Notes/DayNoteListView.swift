import SwiftUI
import SwiftData

struct DayNoteListView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var editingNote: DayNote?

    private var sorted: [DayNote] {
        trip.dayNotes.sorted { $0.day < $1.day }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                EmptyStateView(
                    iconName: "note.text",
                    title: "No Notes Yet",
                    message: "Jot down reminders or plans for specific days.",
                    actionTitle: "Add Note"
                ) {
                    isAdding = true
                }
            } else {
                List {
                    ForEach(sorted) { note in
                        Button {
                            editingNote = note
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(note.day.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(note.title)
                                    .font(.system(.body, design: .rounded).weight(.semibold))
                                if !note.content.isEmpty {
                                    Text(note.content)
                                        .font(.caption)
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
