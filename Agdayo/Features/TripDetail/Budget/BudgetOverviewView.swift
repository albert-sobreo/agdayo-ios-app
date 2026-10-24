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

    // MARK: Design

    private var accent: Color { trip.theme.accentColor }

    private var isOverBudget: Bool {
        trip.overallBudget > 0 && actualSpentTotal > trip.overallBudget
    }

    private var spentFraction: Double {
        guard trip.overallBudget > 0 else { return 0 }
        return min(actualSpentTotal / trip.overallBudget, 1)
    }

    /// The summary at the top: what's been spent, against the budget, in the
    /// same blush hero style as the trip header.
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spent")
                    .trackedLabel(11, color: BrandPalette.maroon.opacity(0.75))
                Spacer()
                if trip.overallBudget > 0 {
                    PillTag(
                        text: isOverBudget ? "Over budget" : "On track",
                        background: isOverBudget ? BrandPalette.maroon : BrandPalette.mint,
                        foreground: isOverBudget ? .white : BrandPalette.mintText
                    )
                } else {
                    PillTag(text: "No budget set", background: Color.white.opacity(0.6), foreground: BrandPalette.maroon)
                }
            }

            MoneyAmount(text: actualSpentTotal.formattedCurrency(code: trip.currency), size: 52, color: BrandPalette.maroon)

            BrandProgressTrack(
                fraction: spentFraction,
                fill: isOverBudget ? BrandPalette.maroon : BrandPalette.rose,
                track: BrandPalette.roseTrack,
                height: 8
            )

            HStack {
                Text(trip.overallBudget > 0
                     ? "of \(trip.overallBudget.formattedCurrency(code: trip.currency)) budget"
                     : "Add a category to set a budget")
                Spacer()
                if trip.overallBudget > 0 {
                    Text(isOverBudget
                         ? "\((actualSpentTotal - trip.overallBudget).formattedCurrency(code: trip.currency)) over"
                         : "\((trip.overallBudget - actualSpentTotal).formattedCurrency(code: trip.currency)) left")
                        .fontWeight(.semibold)
                }
            }
            .font(AppFont.outfit(13, relativeTo: .footnote))
            .foregroundStyle(BrandPalette.maroon.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandPalette.blush, in: RoundedRectangle(cornerRadius: AppRadius.card))
    }

    /// Opens the day-by-day chart. The card draws its own chevron, so the link
    /// is hidden behind it (otherwise the list adds a second one).
    private var dailyReportLink: some View {
        ZStack {
            NavigationLink(value: TripSectionRoute.budgetReport) {
                EmptyView()
            }
            .opacity(0)

            MoneyCard {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title3)
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily report")
                            .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                            .foregroundStyle(.primary)
                        Text("Spending day by day, by category")
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Where the spending went, as four tiles like the trip screen's section buttons.
    private var breakdownGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            breakdownTile("map", "Activities", activityCostsTotal)
            breakdownTile("bed.double", "Stays", accommodationCostsTotal)
            breakdownTile("airplane", "Transport", transportCostsTotal)
            breakdownTile("cart", "Other", expenseCostsTotal)
        }
    }

    private func breakdownTile(_ icon: String, _ title: String, _ amount: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(accent)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                MoneyAmount(text: amount.formattedCurrency(code: trip.currency), size: 22)
                Text(title)
                    .font(AppFont.barlowCondensed(14, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .modifier(GlassOrStickerCard(cornerRadius: AppRadius.smallerCard))
    }

    /// A budget line (category or person): name, planned amount, and how much
    /// of it is spent.
    private func budgetLine(icon: String, name: String, planned: Double, spent: Double) -> some View {
        let over = planned > 0 && spent > planned
        let fraction = planned > 0 ? min(spent / planned, 1) : 0
        return MoneyCard {
            HStack(alignment: .top, spacing: 12) {
                MoneyIconBadge(systemName: icon, accentColor: accent)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(name)
                            .font(AppFont.outfit(16, weight: .semibold, relativeTo: .body))
                        Spacer()
                        MoneyAmount(text: planned.formattedCurrency(code: trip.currency), size: 22)
                    }
                    BrandProgressTrack(
                        fraction: fraction,
                        fill: over ? BrandPalette.maroon : BrandPalette.rose,
                        track: BrandPalette.roseTrack,
                        height: 6
                    )
                    Text(over
                         ? "\(spent.formattedCurrency(code: trip.currency)) spent, over by \((spent - planned).formattedCurrency(code: trip.currency))"
                         : "\(spent.formattedCurrency(code: trip.currency)) spent")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(over ? BrandPalette.maroon : Color.secondary)
                }
            }
        }
    }

    /// A costed item (activity, stay, transport or expense) with what it's
    /// tagged to and its amount, converted to the trip's currency when needed.
    private func itemCard(
        icon: String,
        title: String,
        attachment: String?,
        amount: String,
        converted: String?,
        showsChevron: Bool = false
    ) -> some View {
        MoneyCard {
            HStack(spacing: 12) {
                MoneyIconBadge(systemName: icon, accentColor: accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                        .lineLimit(2)
                    if let attachment {
                        PillTag(text: attachment, background: accent.opacity(0.14), foreground: accent)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    MoneyAmount(text: amount, size: 20)
                    if let converted {
                        Text("≈ \(converted)")
                            .font(AppFont.outfit(11, relativeTo: .caption2))
                            .foregroundStyle(.secondary)
                    }
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func convertedText(currency: String?, converted: Double?) -> String? {
        guard let currency, currency != trip.currency, let converted else { return nil }
        return converted.formattedCurrency(code: trip.currency)
    }

    private func header(_ title: String, _ icon: String) -> some View {
        MoneySectionHeader(title: title, iconName: icon, accentColor: accent)
    }

    var body: some View {
        List {
            Section {
                heroCard.moneyRow()
                dailyReportLink.moneyRow()
                breakdownGrid.moneyRow()
            }

            Section {
                if budgetCategories.isEmpty {
                    emptyNote("No budget categories yet. Add one to start planning your spending.")
                        .moneyRow()
                } else {
                    ForEach(budgetCategories) { category in
                        Button {
                            editingCategory = category
                        } label: {
                            budgetLine(icon: "tag", name: category.name, planned: category.amount, spent: spent(for: category))
                        }
                        .buttonStyle(.plain)
                        .moneyRow()
                    }
                    .onDelete(perform: delete)
                }
            } header: {
                header("Categories", "tag")
            }

            if !memberProfiles.isEmpty {
                Section {
                    ForEach(memberProfiles, id: \.uid) { profile in
                        Button {
                            memberBudgetTarget = MemberBudgetTarget(profile: profile)
                        } label: {
                            budgetLine(
                                icon: "person",
                                name: profile.displayName,
                                planned: trip.memberBudgets[profile.uid] ?? 0,
                                spent: spent(forMemberUID: profile.uid)
                            )
                        }
                        .buttonStyle(.plain)
                        .moneyRow()
                    }
                } header: {
                    header("Individual Budgets", "person.2")
                }
            }

            if !costedActivities.isEmpty {
                Section {
                    ForEach(costedActivities) { activity in
                        // The card draws its own chevron, so the link is hidden
                        // behind it (otherwise the list adds a second one).
                        ZStack {
                            NavigationLink {
                                ActivityDetailView(trip: trip, activity: activity, accentColor: accent, memberProfiles: memberProfiles)
                            } label: {
                                EmptyView()
                            }
                            .opacity(0)

                            itemCard(
                                icon: "map",
                                title: activity.title,
                                attachment: attachmentLabel(categoryID: activity.budgetCategoryID, memberUID: activity.budgetMemberUID),
                                amount: (activity.cost ?? 0).formattedCurrency(code: activity.costCurrency ?? trip.currency),
                                converted: convertedText(currency: activity.costCurrency, converted: activity.costAndRate(inTripCurrency: trip.currency)?.cost),
                                showsChevron: true
                            )
                        }
                        .moneyRow()
                    }
                } header: {
                    header("Activities", "map")
                }
            }

            if !costedAccommodations.isEmpty {
                Section {
                    ForEach(costedAccommodations) { accommodation in
                        Button {
                            editingAccommodation = accommodation
                        } label: {
                            itemCard(
                                icon: "bed.double",
                                title: accommodation.name,
                                attachment: attachmentLabel(categoryID: accommodation.budgetCategoryID, memberUID: accommodation.budgetMemberUID),
                                amount: accommodation.totalCost.formattedCurrency(code: trip.currency),
                                converted: nil
                            )
                        }
                        .buttonStyle(.plain)
                        .moneyRow()
                    }
                } header: {
                    header("Stays", "bed.double")
                }
            }

            if !costedSegments.isEmpty {
                Section {
                    ForEach(costedSegments) { segment in
                        Button {
                            editingSegment = segment
                        } label: {
                            itemCard(
                                icon: "airplane",
                                title: "\(segment.departureLocation) → \(segment.arrivalLocation)",
                                attachment: attachmentLabel(categoryID: segment.budgetCategoryID, memberUID: segment.budgetMemberUID),
                                amount: segment.cost.formattedCurrency(code: segment.currency),
                                converted: convertedText(currency: segment.currency, converted: segment.costAndRate(inTripCurrency: trip.currency)?.cost)
                            )
                        }
                        .buttonStyle(.plain)
                        .moneyRow()
                    }
                } header: {
                    header("Transport", "airplane")
                }
            }

            if !sortedExpenses.isEmpty {
                Section {
                    ForEach(sortedExpenses) { expense in
                        Button {
                            editingExpense = expense
                        } label: {
                            itemCard(
                                icon: "cart",
                                title: expense.name,
                                attachment: attachmentLabel(categoryID: expense.budgetCategoryID, memberUID: expense.budgetMemberUID),
                                amount: expense.cost.formattedCurrency(code: expense.costCurrency ?? trip.currency),
                                converted: convertedText(currency: expense.costCurrency, converted: expense.costAndRate(inTripCurrency: trip.currency)?.cost)
                            )
                        }
                        .buttonStyle(.plain)
                        .moneyRow()
                    }
                    .onDelete(perform: deleteExpenses)
                } header: {
                    header("Other Expenses", "cart")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BrandPalette.canvas.ignoresSafeArea())
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

    private func emptyNote(_ text: String) -> some View {
        MoneyCard {
            Text(text)
                .font(AppFont.outfit(14, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
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
