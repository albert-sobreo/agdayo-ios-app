import SwiftUI
import SwiftData
import CoreLocation

struct AIReviewResultsView: View {
    let tripName: String
    let location: String
    let theme: TripTheme
    let startDate: Date
    let endDate: Date
    let overallBudget: Double
    let currency: String
    /// When set, generated activities are appended to this trip instead of
    /// creating a new one (the "Generate More Activities" flow).
    var existingTrip: Trip?
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var drafts: [ActivityDraft]

    init(
        tripName: String,
        location: String,
        theme: TripTheme,
        startDate: Date,
        endDate: Date,
        overallBudget: Double,
        currency: String,
        existingTrip: Trip? = nil,
        itinerary: GeneratedItinerary,
        onSaved: @escaping () -> Void
    ) {
        self.tripName = tripName
        self.location = location
        self.theme = theme
        self.startDate = startDate
        self.endDate = endDate
        self.overallBudget = overallBudget
        self.currency = currency
        self.existingTrip = existingTrip
        self.onSaved = onSaved
        _drafts = State(initialValue: itinerary.activities.map(ActivityDraft.init))
    }

    private var includedCount: Int {
        drafts.filter { $0.isIncluded }.count
    }

    var body: some View {
        List {
            Section {
                Text("Review each suggestion. Verify a location to pin it on the map, or leave it unverified and add the coordinate later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($drafts) { $draft in
                DraftRow(draft: $draft, accentColor: theme.accentColor)
            }
        }
        .navigationTitle("Review Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add \(includedCount) Activities") { save() }
                    .disabled(includedCount == 0)
            }
        }
    }

    private func save() {
        let trip: Trip
        if let existingTrip {
            trip = existingTrip
        } else {
            trip = Trip(
                name: tripName,
                location: location,
                theme: theme,
                startDate: startDate,
                endDate: endDate,
                overallBudget: overallBudget,
                currency: currency
            )
            modelContext.insert(trip)
        }

        for draft in drafts where draft.isIncluded {
            let date = draft.date(basedOn: startDate)
            let activity = Activity(
                title: draft.title,
                activityDescription: draft.activityDescription,
                location: draft.resolvedLocationName ?? draft.locationQuery,
                latitude: draft.coordinate?.latitude,
                longitude: draft.coordinate?.longitude,
                date: date,
                cost: draft.estimatedCost > 0 ? draft.estimatedCost : nil,
                costCurrency: draft.estimatedCost > 0 ? currency : nil,
                iconName: draft.iconName,
                trip: trip
            )
            modelContext.insert(activity)
        }
        onSaved()
    }
}

private struct ActivityDraft: Identifiable {
    let id = UUID()
    var isIncluded = true
    var title: String
    var activityDescription: String
    var locationQuery: String
    var resolvedLocationName: String?
    var coordinate: CLLocationCoordinate2D?
    var dayOffset: Int
    var approximateTime: String
    var estimatedCost: Double
    var iconName: String

    init(generated: GeneratedActivity) {
        title = generated.title
        activityDescription = generated.activityDescription
        locationQuery = generated.suggestedLocationQuery
        dayOffset = generated.dayOffset
        approximateTime = generated.approximateTime
        estimatedCost = generated.estimatedCost
        iconName = generated.iconName
    }

    func date(basedOn startDate: Date) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: dayOffset, to: startDate) ?? startDate
        let parts = approximateTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return day }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
    }
}

private struct DraftRow: View {
    @Binding var draft: ActivityDraft
    let accentColor: Color
    @State private var isVerifying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Toggle("", isOn: $draft.isIncluded)
                    .labelsHidden()
                    .accessibilityLabel("Include \(draft.title)")
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: draft.iconName)
                            .foregroundStyle(accentColor)
                        Text(draft.title)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                    }
                    Text("Day \(draft.dayOffset + 1) · \(draft.approximateTime)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !draft.activityDescription.isEmpty {
                        Text(draft.activityDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .opacity(draft.isIncluded ? 1 : 0.4)

            Button {
                isVerifying = true
            } label: {
                if let resolved = draft.resolvedLocationName {
                    Label(resolved, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.appSuccess)
                } else {
                    Label("Verify Location: \(draft.locationQuery)", systemImage: "mappin.and.ellipse")
                }
            }
            .font(.caption)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $isVerifying) {
            LocationVerificationSheet(query: draft.locationQuery) { name, coordinate in
                draft.resolvedLocationName = name
                draft.coordinate = coordinate
            }
        }
    }
}

private struct LocationVerificationSheet: View {
    let query: String
    let onResolved: (String, CLLocationCoordinate2D?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(query: String, onResolved: @escaping (String, CLLocationCoordinate2D?) -> Void) {
        self.query = query
        self.onResolved = onResolved
        _text = State(initialValue: query)
    }

    var body: some View {
        NavigationStack {
            Form {
                LocationSearchField(
                    placeholder: "Search for the real place",
                    text: $text,
                    onSelect: { name, coordinate in
                        onResolved(name, coordinate)
                        dismiss()
                    }
                )
            }
            .navigationTitle("Verify Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
