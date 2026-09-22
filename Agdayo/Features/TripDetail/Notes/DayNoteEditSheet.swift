import SwiftUI
import SwiftData

struct DayNoteEditSheet: View {
    let trip: Trip
    var editingNote: DayNote?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var day: Date
    @State private var title: String
    @State private var content: String

    init(trip: Trip, editingNote: DayNote? = nil) {
        self.trip = trip
        self.editingNote = editingNote
        _day = State(initialValue: editingNote?.day ?? trip.startDate)
        _title = State(initialValue: editingNote?.title ?? "")
        _content = State(initialValue: editingNote?.content ?? "")
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Day", selection: $day, in: trip.startDate...trip.endDate, displayedComponents: .date)
                TextField("Title", text: $title)
                TextField("Content", text: $content, axis: .vertical)
                    .lineLimit(4...8)
            }
            .navigationTitle(editingNote == nil ? "Add Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let note: DayNote
        if let editingNote {
            note = editingNote
            note.day = day
            note.title = title.trimmingCharacters(in: .whitespaces)
            note.content = content
        } else {
            note = DayNote(day: day, title: title.trimmingCharacters(in: .whitespaces), content: content, trip: trip)
            modelContext.insert(note)
        }
        if trip.ownerUID != nil {
            let tripID = trip.id
            let noteID = note.id
            let dto = note.dto
            Task {
                try? await FirestoreCollectionSync.push(tripID: tripID, collection: "dayNotes", docID: noteID, data: dto)
            }
        }
        dismiss()
    }
}
