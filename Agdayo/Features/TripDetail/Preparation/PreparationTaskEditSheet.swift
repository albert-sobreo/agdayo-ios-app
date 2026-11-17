import SwiftUI
import SwiftData

/// Predefined categories a prep task can be filed under, plus `other` for
/// anything that doesn't fit — its own free-text field is only shown when
/// selected, so `PreparationTask.category` still stores a plain string
/// underneath (unchanged for Firestore sync / grouping in the checklist).
private enum TaskCategoryOption: String, CaseIterable, Identifiable {
    case documents = "Documents"
    case packing = "Packing"
    case essentials = "Essentials"
    case transportation = "Transportation"
    case health = "Health"
    case finance = "Finance"
    case electronics = "Electronics"
    case other = "Other"

    var id: String { rawValue }
}

/// Adds a new prep task, or edits `task` when one is passed in.
struct PreparationTaskEditSheet: View {
    let trip: Trip
    var task: PreparationTask?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var selectedCategory: TaskCategoryOption = .essentials
    @State private var customCategory = ""
    @State private var notes = ""

    init(trip: Trip, task: PreparationTask? = nil) {
        self.trip = trip
        self.task = task
        guard let task else { return }
        _name = State(initialValue: task.name)
        _notes = State(initialValue: task.notes)
        if let option = TaskCategoryOption(rawValue: task.category), option != .other {
            _selectedCategory = State(initialValue: option)
        } else {
            _selectedCategory = State(initialValue: .other)
            _customCategory = State(initialValue: task.category)
        }
    }

    private var resolvedCategory: String {
        selectedCategory == .other ? customCategory.trimmingCharacters(in: .whitespaces) : selectedCategory.rawValue
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !resolvedCategory.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    FormCard(title: "Task", icon: "checklist", accent: trip.theme.accentColor) {
                        FormField("Name") {
                            TextField("Name", text: $name)
                        }
                        FormField {
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(TaskCategoryOption.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        }
                        if selectedCategory == .other {
                            FormField("Custom category") {
                                TextField("Custom Category", text: $customCategory)
                            }
                        }
                    }

                    FormCard(title: "Notes", icon: "note.text", accent: trip.theme.accentColor) {
                        FormField {
                            TextField("Optional notes", text: $notes, axis: .vertical)
                                .lineLimit(3...6)
                        }
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .brandForm(accent: trip.theme.accentColor)
            .navigationTitle(task == nil ? "Add Task" : "Edit Task")
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
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let task: PreparationTask
        if let existing = self.task {
            existing.name = trimmedName
            existing.category = resolvedCategory
            existing.notes = notes
            task = existing
        } else {
            task = PreparationTask(name: trimmedName, category: resolvedCategory, notes: notes, trip: trip)
            modelContext.insert(task)
        }
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
