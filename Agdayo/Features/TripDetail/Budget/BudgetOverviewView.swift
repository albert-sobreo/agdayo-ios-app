import SwiftUI
import SwiftData

struct BudgetOverviewView: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    /// Live queries scoped to this trip rather than relationship traversals
    /// (`trip.budgetCategories`, `trip.activities`, etc., and by extension
    /// `trip.actualSpentTotal`/`trip.activityCostsTotal`/etc. which read
    /// those same relationships internally) — see `ItineraryTimelineView`'s
    /// equivalent property for why those don't reliably refresh live.
    @Query private var budgetCategories: [BudgetCategory]
    @Query private var activities: [Activity]
    @Query private var accommodations: [Accommodation]
    @Query private var transportSegments: [TransportSegment]
    @Query private var expenses: [Expense]

    @Environment(\.modelContext) private var modelContext
    @State private var isAddingCategory = false
    @State private var editingCategory: BudgetCategory?
    @State private var editingAccommodation: Accommodation?
    @State private var editingSegment: TransportSegment?
    @State private var memberBudgetTarget: MemberBudgetTarget?
    @State private var isAddingExpense = false
    @State private var editingExpense: Expense?

    init(trip: Trip, memberProfiles: [AppUserProfile] = []) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        let tripID = trip.id
        _budgetCategories = Query(filter: #Predicate<BudgetCategory> { $0.trip?.id == tripID })
        _activities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID })
        _accommodations = Query(filter: #Predicate<Accommodation> { $0.trip?.id == tripID })
        _transportSegments = Query(filter: #Predicate<TransportSegment> { $0.trip?.id == tripID })
        _expenses = Query(filter: #Predicate<Expense> { $0.trip?.id == tripID })
    }

    /// The trip's overall budget — always this, kept in sync by
    /// `TripMembershipService.syncOverallBudget(for:)` whenever a category
    /// changes, rather than entered separately.
    private var categoriesTotal: Double {
        budgetCategories.reduce(0) { $0 + $1.amount }
    }

    /// Same conversion `Trip.activityCostsTotal` does, just against the
    /// locally-queried `activities` instead of the relationship traversal.
    private var activityCostsTotal: Double {
        activities.reduce(0) { $0 + ($1.costAndRate(inTripCurrency: trip.currency)?.cost ?? 0) }
    }

    private var accommodationCostsTotal: Double {
        accommodations.reduce(0) { $0 + $1.totalCost }
    }

    private var transportCostsTotal: Double {
        transportSegments.reduce(0) { $0 + ($1.costAndRate(inTripCurrency: trip.currency)?.cost ?? 0) }
    }

    private var expenseCostsTotal: Double {
        expenses.reduce(0) { $0 + ($1.costAndRate(inTripCurrency: trip.currency)?.cost ?? 0) }
    }

    /// Money actually committed — categories are planned budget, not an
    /// expense, so they're deliberately excluded (see `Trip.actualSpentTotal`).
    private var actualSpentTotal: Double {
        activityCostsTotal + accommodationCostsTotal + transportCostsTotal + expenseCostsTotal
    }

    /// Sum of every costed item tagged with this category, across all four
    /// expense types — the planned-vs-actual figure shown per category.
    private func spent(for category: BudgetCategory) -> Double {
        spent(activityFilter: { $0.budgetCategoryID == category.id },
              accommodationFilter: { $0.budgetCategoryID == category.id },
              transportFilter: { $0.budgetCategoryID == category.id },
              expenseFilter: { $0.budgetCategoryID == category.id })
    }

    /// Same idea, but for a member's individual budget attachment instead
    /// of a category.
    private func spent(forMemberUID uid: String) -> Double {
        spent(activityFilter: { $0.budgetMemberUID == uid },
              accommodationFilter: { $0.budgetMemberUID == uid },
              transportFilter: { $0.budgetMemberUID == uid },
              expenseFilter: { $0.budgetMemberUID == uid })
    }

    private func spent(
        activityFilter: (Activity) -> Bool,
        accommodationFilter: (Accommodation) -> Bool,
        transportFilter: (TransportSegment) -> Bool,
        expenseFilter: (Expense) -> Bool
    ) -> Double {
        let activitySpent = activities
            .filter(activityFilter)
            .reduce(0) { $0 + ($1.costAndRate(inTripCurrency: trip.currency)?.cost ?? 0) }
        let accommodationSpent = accommodations
            .filter(accommodationFilter)
            .reduce(0) { $0 + $1.totalCost }
        let transportSpent = transportSegments
            .filter(transportFilter)
            .reduce(0) { $0 + ($1.costAndRate(inTripCurrency: trip.currency)?.cost ?? 0) }
        let expenseSpent = expenses
            .filter(expenseFilter)
            .reduce(0) { $0 + ($1.costAndRate(inTripCurrency: trip.currency)?.cost ?? 0) }
        return activitySpent + accommodationSpent + transportSpent + expenseSpent
    }

    /// Label for whichever of `budgetCategoryID`/`budgetMemberUID` is set on
    /// an item, for display as its row subtitle — `nil` when neither is.
    private func attachmentLabel(categoryID: UUID?, memberUID: String?) -> String? {
        if let categoryID {
            return budgetCategories.first { $0.id == categoryID }?.name
        }
        if let memberUID {
            return memberProfiles.first { $0.uid == memberUID }?.displayName
        }
        return nil
    }

    private var costedActivities: [Activity] {
        activities.filter { $0.cost != nil }.sorted { $0.date < $1.date }
    }

    private var costedAccommodations: [Accommodation] {
        accommodations.filter { $0.totalCost > 0 }.sorted { $0.startDate < $1.startDate }
    }

    private var costedSegments: [TransportSegment] {
        transportSegments.filter { $0.cost > 0 }.sorted { $0.departureDate < $1.departureDate }
    }

    private var sortedExpenses: [Expense] {
        expenses.sorted { ($0.dateTime ?? .distantPast) > ($1.dateTime ?? .distantPast) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    BudgetProgressBar(spent: actualSpentTotal, total: trip.overallBudget, currency: trip.currency)
                    Text("Planned: \(categoriesTotal.formattedCurrency(code: trip.currency)) · Spent — Activities: \(activityCostsTotal.formattedCurrency(code: trip.currency)) · Stays: \(accommodationCostsTotal.formattedCurrency(code: trip.currency)) · Transport: \(transportCostsTotal.formattedCurrency(code: trip.currency)) · Other: \(expenseCostsTotal.formattedCurrency(code: trip.currency))")
                        .font(AppFont.outfit(11, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Categories") {
                if budgetCategories.isEmpty {
                    Text("No budget categories yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(budgetCategories) { category in
                        Button {
                            editingCategory = category
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(category.name)
                                    Text("\(spent(for: category).formattedCurrency(code: trip.currency)) spent")
                                        .font(AppFont.outfit(11, relativeTo: .caption2))
                                        .foregroundStyle(.secondary)
                                }
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

            if !memberProfiles.isEmpty {
                Section("Individual Budgets") {
                    ForEach(memberProfiles, id: \.uid) { profile in
                        Button {
                            memberBudgetTarget = MemberBudgetTarget(profile: profile)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                    Text("\(spent(forMemberUID: profile.uid).formattedCurrency(code: trip.currency)) spent")
                                        .font(AppFont.outfit(11, relativeTo: .caption2))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text((trip.memberBudgets[profile.uid] ?? 0).formattedCurrency(code: trip.currency))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !costedActivities.isEmpty {
                Section("Activities") {
                    ForEach(costedActivities) { activity in
                        NavigationLink {
                            ActivityDetailView(trip: trip, activity: activity, accentColor: trip.theme.accentColor, memberProfiles: memberProfiles)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(activity.title)
                                    if let label = attachmentLabel(categoryID: activity.budgetCategoryID, memberUID: activity.budgetMemberUID) {
                                        Text(label)
                                            .font(AppFont.outfit(11, relativeTo: .caption2))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text((activity.cost ?? 0).formattedCurrency(code: activity.costCurrency ?? trip.currency))
                                        .foregroundStyle(.secondary)
                                    if let costCurrency = activity.costCurrency, costCurrency != trip.currency,
                                       let converted = activity.costAndRate(inTripCurrency: trip.currency)?.cost {
                                        Text("≈ \(converted.formattedCurrency(code: trip.currency))")
                                            .font(AppFont.outfit(11, relativeTo: .caption2))
                                            .foregroundStyle(.secondary.opacity(0.7))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if !costedAccommodations.isEmpty {
                Section("Accommodations") {
                    ForEach(costedAccommodations) { accommodation in
                        Button {
                            editingAccommodation = accommodation
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(accommodation.name)
                                    if let label = attachmentLabel(categoryID: accommodation.budgetCategoryID, memberUID: accommodation.budgetMemberUID) {
                                        Text(label)
                                            .font(AppFont.outfit(11, relativeTo: .caption2))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(accommodation.totalCost.formattedCurrency(code: trip.currency))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !costedSegments.isEmpty {
                Section("Transport") {
                    ForEach(costedSegments) { segment in
                        Button {
                            editingSegment = segment
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(segment.departureLocation) → \(segment.arrivalLocation)")
                                    if let label = attachmentLabel(categoryID: segment.budgetCategoryID, memberUID: segment.budgetMemberUID) {
                                        Text(label)
                                            .font(AppFont.outfit(11, relativeTo: .caption2))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(segment.cost.formattedCurrency(code: segment.currency))
                                        .foregroundStyle(.secondary)
                                    if segment.currency != trip.currency,
                                       let converted = segment.costAndRate(inTripCurrency: trip.currency)?.cost {
                                        Text("≈ \(converted.formattedCurrency(code: trip.currency))")
                                            .font(AppFont.outfit(11, relativeTo: .caption2))
                                            .foregroundStyle(.secondary.opacity(0.7))
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !sortedExpenses.isEmpty {
                Section("Other Expenses") {
                    ForEach(sortedExpenses) { expense in
                        Button {
                            editingExpense = expense
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(expense.name)
                                    if let label = attachmentLabel(categoryID: expense.budgetCategoryID, memberUID: expense.budgetMemberUID) {
                                        Text(label)
                                            .font(AppFont.outfit(11, relativeTo: .caption2))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(expense.cost.formattedCurrency(code: expense.costCurrency ?? trip.currency))
                                        .foregroundStyle(.secondary)
                                    if let costCurrency = expense.costCurrency, costCurrency != trip.currency,
                                       let converted = expense.costAndRate(inTripCurrency: trip.currency)?.cost {
                                        Text("≈ \(converted.formattedCurrency(code: trip.currency))")
                                            .font(AppFont.outfit(11, relativeTo: .caption2))
                                            .foregroundStyle(.secondary.opacity(0.7))
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteExpenses)
                }
            }
        }
        .navigationTitle("Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Add Category", systemImage: "tag") { isAddingCategory = true }
                    Button("Add Expense", systemImage: "cart") { isAddingExpense = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
            }
        }
        .sheet(isPresented: $isAddingCategory) {
            BudgetCategoryEditSheet(trip: trip)
        }
        .sheet(isPresented: $isAddingExpense) {
            ExpenseEditSheet(trip: trip, memberProfiles: memberProfiles)
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseEditSheet(trip: trip, editingExpense: expense, memberProfiles: memberProfiles)
        }
        .sheet(item: $editingCategory) { category in
            BudgetCategoryEditSheet(trip: trip, editingCategory: category)
        }
        .sheet(item: $memberBudgetTarget) { target in
            MemberBudgetEditSheet(trip: trip, profile: target.profile)
        }
        .sheet(item: $editingAccommodation) { accommodation in
            AccommodationEditSheet(trip: trip, editingAccommodation: accommodation, memberProfiles: memberProfiles)
        }
        .sheet(item: $editingSegment) { segment in
            TransportSegmentEditSheet(trip: trip, editingSegment: segment, memberProfiles: memberProfiles)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let category = budgetCategories[index]
            if trip.ownerUID != nil {
                let tripID = trip.id
                let categoryID = category.id
                Task {
                    try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "budgetCategories", docID: categoryID)
                }
            }
            modelContext.delete(category)
        }
        TripMembershipService.syncOverallBudget(for: trip)
    }

    private func deleteExpenses(at offsets: IndexSet) {
        for index in offsets {
            let expense = sortedExpenses[index]
            if trip.ownerUID != nil {
                let tripID = trip.id
                let expenseID = expense.id
                Task {
                    try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "expenses", docID: expenseID)
                }
            }
            modelContext.delete(expense)
        }
    }
}

private struct MemberBudgetTarget: Identifiable {
    var id: String { profile.uid }
    let profile: AppUserProfile
}

private struct MemberBudgetEditSheet: View {
    let trip: Trip
    let profile: AppUserProfile

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String

    init(trip: Trip, profile: AppUserProfile) {
        self.trip = trip
        self.profile = profile
        let amount = trip.memberBudgets[profile.uid] ?? 0
        _amountText = State(initialValue: amount == 0 ? "" : String(amount))
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Budget", text: $amountText)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle(profile.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        trip.memberBudgets[profile.uid] = Double(amountText) ?? 0
                        TripMembershipService.pushTripFieldsUpdate(trip: trip)
                        dismiss()
                    }
                }
            }
        }
    }
}
