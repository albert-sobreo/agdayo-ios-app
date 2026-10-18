import SwiftUI
import SwiftData

struct PreparationChecklistView: View {
    let trip: Trip

    /// Live query scoped to this trip rather than a `trip.preparationTasks`
    /// traversal — see `ItineraryTimelineView`'s equivalent property for why.
    @Query private var preparationTasks: [PreparationTask]

    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var filter: PreparationFilter = .all

    init(trip: Trip) {
        self.trip = trip
        let tripID = trip.id
        _preparationTasks = Query(filter: #Predicate<PreparationTask> { $0.trip?.id == tripID })
    }

    private var filtered: [PreparationTask] {
        switch filter {
        case .all: return preparationTasks
        case .completed: return preparationTasks.filter { $0.completed }
        case .notCompleted: return preparationTasks.filter { !$0.completed }
        }
    }

    private var groupedByCategory: [(category: String, tasks: [PreparationTask])] {
        let grouped = Dictionary(grouping: filtered) { $0.category }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    private var accent: Color { trip.theme.accentColor }

    var body: some View {
        Group {
            if preparationTasks.isEmpty {
                EmptyStateView(
                    iconName: "checklist",
                    title: "No Prep Tasks Yet",
                    message: "Add packing, documents, or other things to prepare.",
                    actionTitle: "Add Task",
                    action: { isAdding = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandPalette.canvas.ignoresSafeArea())
            } else {
                List {
                    Section {
                        progressCard.moneyRow()
                        Picker("Filter", selection: $filter) {
                            ForEach(PreparationFilter.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .moneyRow()
                    }

                    ForEach(groupedByCategory, id: \.category) { group in
                        Section {
                            ForEach(group.tasks) { task in
                                PreparationTaskRow(task: task, trip: trip, accentColor: accent)
                                    .moneyRow()
                            }
                            .onDelete { offsets in delete(tasks: group.tasks, at: offsets) }
                        } header: {
                            HStack {
                                MoneySectionHeader(title: group.category, iconName: "tag", accentColor: accent)
                                Text("\(group.tasks.filter(\.completed).count)/\(group.tasks.count)")
                                    .font(AppFont.barlowCondensed(18, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(BrandPalette.canvas.ignoresSafeArea())
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

    /// How much is done, as a big count with a progress bar in the trip's color.
    private var progressCard: some View {
        let done = preparationTasks.filter(\.completed).count
        let total = preparationTasks.count
        return MoneyCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("READY TO GO")
                    .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    MoneyAmount(text: "\(done)", size: 44, color: accent)
                    Text("of \(total) done")
                        .font(AppFont.outfit(15, relativeTo: .subheadline))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if total > 0, done == total {
                        Label("All set", systemImage: "checkmark.seal.fill")
                            .font(AppFont.outfit(13, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(Color.appSuccess)
                    }
                }
                BrandProgressTrack(
                    fraction: total == 0 ? 0 : Double(done) / Double(total),
                    fill: accent,
                    track: accent.opacity(0.15),
                    height: 8
                )
            }
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
    let accentColor: Color

    var body: some View {
        Button {
            withAnimation(.snappy) { task.completed.toggle() }
            if trip.ownerUID != nil {
                let tripID = trip.id
                let taskID = task.id
                let dto = task.dto
                Task {
                    try? await FirestoreCollectionSync.push(tripID: tripID, collection: "preparationTasks", docID: taskID, data: dto)
                }
            }
        } label: {
            MoneyCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.completed ? Color.appSuccess : accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.name)
                            .font(AppFont.outfit(16, weight: .semibold, relativeTo: .body))
                            .strikethrough(task.completed)
                            .foregroundStyle(task.completed ? .secondary : .primary)
                        if !task.notes.isEmpty {
                            Text(task.notes)
                                .font(AppFont.outfit(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
