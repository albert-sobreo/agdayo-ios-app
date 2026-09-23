import SwiftUI
import SwiftData

struct PreparationTaskEditSheet: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var category = "Essentials"
    @State private var notes = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Name", text: $name)
                    TextField("Category", text: $category)
                    HStack {
                        ForEach(PreparationTaskSuggestion.defaults, id: \.self) { suggestion in
                            Button(suggestion) { category = suggestion }
                                .font(AppFont.outfit(12, relativeTo: .caption))
                                .buttonStyle(.bordered)
                        }
                    }
                }
                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Task")
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
        let task = PreparationTask(
            name: name.trimmingCharacters(in: .whitespaces),
            category: category.trimmingCharacters(in: .whitespaces),
            notes: notes,
            trip: trip
        )
        modelContext.insert(task)
        if trip.ownerUID != nil {
            let tripID = trip.id
            let taskID = task.id
            let dto = task.dto
            Task {
                try? await FirestoreCollectionSync.push(tripID: tripID, collection: "preparationTasks", docID: taskID, data: dto)
            }
        }
        dismiss()
    }
}
