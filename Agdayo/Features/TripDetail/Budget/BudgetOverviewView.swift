import SwiftUI
import SwiftData

struct BudgetOverviewView: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    @Environment(\.modelContext) private var modelContext
    @State private var isAddingCategory = false
    @State private var editingCategory: BudgetCategory?
    @State private var isEditingOverallBudget = false
    @State private var editingAccommodation: Accommodation?
    @State private var editingSegment: TransportSegment?

    private var categoriesTotal: Double {
        trip.budgetCategories.reduce(0) { $0 + $1.amount }
    }

    private var costedActivities: [Activity] {
        trip.activities.filter { $0.cost != nil }.sorted { $0.date < $1.date }
    }

    private var costedAccommodations: [Accommodation] {
        trip.accommodations.filter { $0.totalCost > 0 }.sorted { $0.startDate < $1.startDate }
    }

    private var costedSegments: [TransportSegment] {
        trip.transportSegments.filter { $0.cost > 0 }.sorted { $0.departureDate < $1.departureDate }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    BudgetProgressBar(spent: trip.budgetedTotal, total: trip.overallBudget, currency: trip.currency)
                    Text("Categories: \(categoriesTotal.formattedCurrency(code: trip.currency)) · Activities: \(trip.activityCostsTotal.formattedCurrency(code: trip.currency)) · Stays: \(trip.accommodationCostsTotal.formattedCurrency(code: trip.currency)) · Transport: \(trip.transportCostsTotal.formattedCurrency(code: trip.currency))")
                        .font(AppFont.outfit(11, relativeTo: .caption2))
                        .foregroundStyle(.secondary)
                    Button("Edit Overall Budget") { isEditingOverallBudget = true }
                        .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
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

            if !costedActivities.isEmpty {
                Section("Activities") {
                    ForEach(costedActivities) { activity in
                        NavigationLink {
                            ActivityDetailView(trip: trip, activity: activity, accentColor: trip.theme.accentColor, memberProfiles: memberProfiles)
                        } label: {
                            HStack {
                                Text(activity.title)
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
                                Text(accommodation.name)
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
                                Text("\(segment.departureLocation) → \(segment.arrivalLocation)")
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
        .sheet(isPresented: $isEditingOverallBudget) {
            OverallBudgetEditSheet(trip: trip)
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
                            let latitude = trip.latitude
                            let longitude = trip.longitude
                            Task {
                                try? await TripMembershipService.updateTripRecord(
                                    tripID: tripID, name: name, location: location,
                                    theme: theme, startDate: startDate, endDate: endDate,
                                    overallBudget: overallBudget, currency: currency, tripDescription: tripDescription,
                                    latitude: latitude, longitude: longitude
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
