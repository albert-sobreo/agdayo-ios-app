import SwiftUI
import SwiftData

struct BudgetCategoryEditSheet: View {
    let trip: Trip
    var editingCategory: BudgetCategory?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var amountText: String

    init(trip: Trip, editingCategory: BudgetCategory? = nil) {
        self.trip = trip
        self.editingCategory = editingCategory
        _name = State(initialValue: editingCategory?.name ?? "")
        // An empty field is friendlier to edit than a literal "0.0" the
        // user has to delete first.
        let amount = editingCategory?.amount ?? 0
        _amountText = State(initialValue: amount == 0 ? "" : String(amount))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Category, e.g. Flights", text: $name)
                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle(editingCategory == nil ? "Add Category" : "Edit Category")
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
        let amount = Double(amountText) ?? 0
        let category: BudgetCategory
        if let editingCategory {
            category = editingCategory
            category.name = name.trimmingCharacters(in: .whitespaces)
            category.amount = amount
        } else {
            category = BudgetCategory(name: name.trimmingCharacters(in: .whitespaces), amount: amount, trip: trip)
            modelContext.insert(category)
        }
        if trip.ownerUID != nil {
            let tripID = trip.id
            let categoryID = category.id
            let dto = category.dto
            Task {
                try? await FirestoreCollectionSync.push(tripID: tripID, collection: "budgetCategories", docID: categoryID, data: dto)
            }
        }
        // Categories are the trip's planned budget, not an expense — the
        // overall budget is always their sum, recomputed here.
        TripMembershipService.syncOverallBudget(for: trip)
        dismiss()
    }
}
