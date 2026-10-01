import SwiftUI

/// "Which planned budget category — or which member's individual budget —
/// does this expense count against." Shared by the Activity/Accommodation/
/// Transport/Expense edit sheets so costs roll up into the Budget page's
/// planned-vs-actual breakdown. Exactly one of `categoryID`/`memberUID` is
/// ever set; picking one clears the other.
struct BudgetCategoryPicker: View {
    let categories: [BudgetCategory]
    var memberProfiles: [AppUserProfile] = []
    @Binding var categoryID: UUID?
    @Binding var memberUID: String?

    private enum Selection: Hashable {
        case category(UUID)
        case member(String)
    }

    private var selection: Binding<Selection?> {
        Binding(
            get: {
                if let categoryID { return .category(categoryID) }
                if let memberUID { return .member(memberUID) }
                return nil
            },
            set: { newValue in
                switch newValue {
                case .category(let id):
                    categoryID = id
                    memberUID = nil
                case .member(let uid):
                    memberUID = uid
                    categoryID = nil
                case nil:
                    categoryID = nil
                    memberUID = nil
                }
            }
        )
    }

    var body: some View {
        Picker("Budget Category", selection: selection) {
            Text("None").tag(Selection?.none)
            if !categories.isEmpty {
                Section("Categories") {
                    ForEach(categories.sorted { $0.name < $1.name }) { category in
                        Text(category.name).tag(Selection?.some(.category(category.id)))
                    }
                }
            }
            if !memberProfiles.isEmpty {
                Section("Individual Budgets") {
                    ForEach(memberProfiles, id: \.uid) { profile in
                        Text(profile.displayName).tag(Selection?.some(.member(profile.uid)))
                    }
                }
            }
        }
    }
}
