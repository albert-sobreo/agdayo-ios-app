import SwiftUI
import SwiftData

struct PreparationChecklistView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var filter: PreparationFilter = .all

    private var filtered: [PreparationTask] {
        switch filter {
        case .all: return trip.preparationTasks
        case .completed: return trip.preparationTasks.filter { $0.completed }
        case .notCompleted: return trip.preparationTasks.filter { !$0.completed }
        }
    }

    private var groupedByCategory: [(category: String, tasks: [PreparationTask])] {
        let grouped = Dictionary(grouping: filtered) { $0.category }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        Group {
            if trip.preparationTasks.isEmpty {
                EmptyStateView(
                    iconName: "checklist",
                    title: "No Prep Tasks Yet",
                    message: "Add packing, documents, or other things to prepare.",
                    actionTitle: "Add Task",
                    action: { isAdding = true }
                )
            } else {
                List {
                    Section {
                        Picker("Filter", selection: $filter) {
                            ForEach(PreparationFilter.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    ForEach(groupedByCategory, id: \.category) { group in
                        Section(group.category) {
                            ForEach(group.tasks) { task in
                                PreparationTaskRow(task: task, trip: trip)
                            }
                            .onDelete { offsets in delete(tasks: group.tasks, at: offsets) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Preparation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Add Task", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            PreparationTaskEditSheet(trip: trip)
        }
    }

    private func delete(tasks: [PreparationTask], at offsets: IndexSet) {
        for index in offsets {
            let task = tasks[index]
            if trip.ownerUID != nil {
                let tripID = trip.id
                let taskID = task.id
                Task {
                    try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "preparationTasks", docID: taskID)
                }
            }
            modelContext.delete(task)
        }
    }
}

private enum PreparationFilter: CaseIterable {
    case all, completed, notCompleted

    var label: String {
        switch self {
        case .all: return "All"
        case .completed: return "Completed"
        case .notCompleted: return "Not Completed"
        }
    }
}

private struct PreparationTaskRow: View {
    @Bindable var task: PreparationTask
    let trip: Trip

    var body: some View {
        Button {
            task.completed.toggle()
            if trip.ownerUID != nil {
                let tripID = trip.id
                let taskID = task.id
                let dto = task.dto
                Task {
                    try? await FirestoreCollectionSync.push(tripID: tripID, collection: "preparationTasks", docID: taskID, data: dto)
                }
            }
        } label: {
            HStack {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.completed ? Color.appSuccess : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.name)
                        .strikethrough(task.completed)
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
