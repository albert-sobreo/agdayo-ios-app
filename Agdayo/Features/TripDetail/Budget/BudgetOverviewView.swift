import SwiftUI
import SwiftData

struct BudgetOverviewView: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @State private var isAddingCategory = false
    @State private var editingCategory: BudgetCategory?
    @State private var isEditingOverallBudget = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    BudgetProgressBar(spent: trip.budgetedTotal, total: trip.overallBudget, currency: trip.currency)
                    Button("Edit Overall Budget") { isEditingOverallBudget = true }
                        .font(.caption.weight(.semibold))
                }
            }

            Section("Categories") {
                if trip.budgetCategories.isEmpty {
                    Text("No budget categories yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(trip.budgetCategories) { category in
                        Button {
                            editingCategory = category
                        } label: {
                            HStack {
                                Text(category.name)
                                Spacer()
                                Text(category.amount.formattedCurrency(code: trip.currency))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAddingCategory = true } label: {
                    Label("Add Category", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingCategory) {
            BudgetCategoryEditSheet(trip: trip)
        }
        .sheet(item: $editingCategory) { category in
            BudgetCategoryEditSheet(trip: trip, editingCategory: category)
        }
        .sheet(isPresented: $isEditingOverallBudget) {
            OverallBudgetEditSheet(trip: trip)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let category = trip.budgetCategories[index]
            if trip.ownerUID != nil {
                let tripID = trip.id
                let categoryID = category.id
                Task {
                    try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "budgetCategories", docID: categoryID)
                }
            }
            modelContext.delete(category)
        }
    }
}

private struct OverallBudgetEditSheet: View {
    let trip: Trip
    @Environment(\.dismiss) private var dismiss
    @State private var overallBudgetText: String
    @State private var currency: String

    init(trip: Trip) {
        self.trip = trip
        _overallBudgetText = State(initialValue: String(trip.overallBudget))
        _currency = State(initialValue: trip.currency)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Overall Budget", text: $overallBudgetText)
                    .keyboardType(.decimalPad)
                Picker("Currency", selection: $currency) {
                    ForEach(CurrencyCode.common, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            }
            .navigationTitle("Overall Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        trip.overallBudget = Double(overallBudgetText) ?? 0
                        trip.currency = currency
                        if trip.ownerUID != nil {
                            let tripID = trip.id
                            let name = trip.name
                            let location = trip.location
                            let theme = trip.theme.rawValue
                            let startDate = trip.startDate
                            let endDate = trip.endDate
                            let overallBudget = trip.overallBudget
                            let currency = trip.currency
                            let tripDescription = trip.tripDescription
                            Task {
                                try? await TripMembershipService.updateTripRecord(
                                    tripID: tripID, name: name, location: location,
                                    theme: theme, startDate: startDate, endDate: endDate,
                                    overallBudget: overallBudget, currency: currency, tripDescription: tripDescription
                                )
                            }
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
