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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandPalette.canvas.ignoresSafeArea())
            } else {
                List {
                    ForEach(sorted) { note in
                        Button {
                            editingNote = note
                        } label: {
                            NoteCard(note: note, accentColor: trip.theme.accentColor)
                        }
                        .buttonStyle(.plain)
                        .moneyRow()
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(BrandPalette.canvas.ignoresSafeArea())
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

/// A note as a card: the day as a date tile in the trip's color, then the
/// title and a preview of the text.
private struct NoteCard: View {
    let note: DayNote
    let accentColor: Color

    var body: some View {
        MoneyCard {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    Text(note.day.formatted(.dateTime.month(.abbreviated)))
                        .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(note.day.formatted(.dateTime.day()))
                        .font(AppFont.barlowCondensed(28, weight: .semibold))
                }
                .foregroundStyle(accentColor)
                .frame(width: 52, height: 56)
                .background(accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(AppFont.barlowCondensed(22, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(note.day.formatted(.dateTime.weekday(.wide)))
                        .font(AppFont.outfit(11, weight: .medium, relativeTo: .caption2))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    if !note.content.isEmpty {
                        Text(note.content)
                            .font(AppFont.outfit(14, relativeTo: .subheadline))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}
