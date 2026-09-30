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

    @Environment(\.modelContext) private var modelContext
    @State private var isAddingCategory = false
    @State private var editingCategory: BudgetCategory?
    @State private var editingAccommodation: Accommodation?
    @State private var editingSegment: TransportSegment?
    @State private var memberBudgetTarget: MemberBudgetTarget?

    init(trip: Trip, memberProfiles: [AppUserProfile] = []) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        let tripID = trip.id
        _budgetCategories = Query(filter: #Predicate<BudgetCategory> { $0.trip?.id == tripID })
        _activities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID })
        _accommodations = Query(filter: #Predicate<Accommodation> { $0.trip?.id == tripID })
        _transportSegments = Query(filter: #Predicate<TransportSegment> { $0.trip?.id == tripID })
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

    /// Money actually committed — categories are planned budget, not an
    /// expense, so they're deliberately excluded (see `Trip.actualSpentTotal`).
    private var actualSpentTotal: Double {
        activityCostsTotal + accommodationCostsTotal + transportCostsTotal
    }

    /// Sum of every costed item tagged with this category, across all three
    /// expense types — the planned-vs-actual figure shown per category.
    private func spent(for category: BudgetCategory) -> Double {
        let activitySpent = activities
            .filter { $0.budgetCategoryID == category.id }
            .reduce(0) { $0 + ($1.costAndRate(inTripCurrency: trip.currency)?.cost ?? 0) }
        let accommodationSpent = accommodations
            .filter { $0.budgetCategoryID == category.id }
            .reduce(0) { $0 + $1.totalCost }
        let transportSpent = transportSegments
            .filter { $0.budgetCategoryID == category.id }
            .reduce(0) { $0 + ($1.costAndRate(inTripCurrency: trip.currency)?.cost ?? 0) }
        return activitySpent + accommodationSpent + transportSpent
    }

    private func categoryName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return budgetCategories.first { $0.id == id }?.name
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

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    BudgetProgressBar(spent: actualSpentTotal, total: trip.overallBudget, currency: trip.currency)
                    Text("Planned: \(categoriesTotal.formattedCurrency(code: trip.currency)) · Spent — Activities: \(activityCostsTotal.formattedCurrency(code: trip.currency)) · Stays: \(accommodationCostsTotal.formattedCurrency(code: trip.currency)) · Transport: \(transportCostsTotal.formattedCurrency(code: trip.currency))")
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
                                Text(profile.displayName)
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
                                    if let categoryName = categoryName(for: activity.budgetCategoryID) {
                                        Text(categoryName)
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
                                    if let categoryName = categoryName(for: accommodation.budgetCategoryID) {
                                        Text(categoryName)
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
                                    if let categoryName = categoryName(for: segment.budgetCategoryID) {
                                        Text(categoryName)
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
