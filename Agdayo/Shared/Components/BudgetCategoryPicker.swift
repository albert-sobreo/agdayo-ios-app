import SwiftUI

/// "Which planned budget category does this expense count against" —
/// shared by the Activity/Accommodation/Transport edit sheets so their
/// costs can roll up into the Budget page's planned-vs-actual breakdown.
struct BudgetCategoryPicker: View {
    let categories: [BudgetCategory]
    @Binding var selection: UUID?

    var body: some View {
        Picker("Budget Category", selection: $selection) {
            Text("None").tag(UUID?.none)
            ForEach(categories.sorted { $0.name < $1.name }) { category in
                Text(category.name).tag(Optional(category.id))
            }
        }
    }
}
