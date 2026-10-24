import SwiftUI
import FirebaseAuth

struct TripSettingsView: View {
    let trip: Trip
    var onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService

    @State private var name: String
    @State private var location: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var theme: TripTheme
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var currency: String
    @State private var tripDescription: String
    @State private var isShowingDeleteConfirmation = false
    @State private var isConfirmingDiscard = false

    /// Whether anything differs from the saved trip.
    private var hasChanges: Bool {
        name != trip.name || location != trip.location || theme != trip.theme
            || startDate != trip.startDate || endDate != trip.endDate
            || currency != trip.currency || tripDescription != trip.tripDescription
    }

    init(trip: Trip, onDeleted: @escaping () -> Void) {
        self.trip = trip
        self.onDeleted = onDeleted
        _name = State(initialValue: trip.name)
        _location = State(initialValue: trip.location)
        _latitude = State(initialValue: trip.latitude)
        _longitude = State(initialValue: trip.longitude)
        _theme = State(initialValue: trip.theme)
        _startDate = State(initialValue: trip.startDate)
        _endDate = State(initialValue: trip.endDate)
        _currency = State(initialValue: trip.currency)
        _tripDescription = State(initialValue: trip.tripDescription)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !location.trimmingCharacters(in: .whitespaces).isEmpty
            && startDate <= endDate
    }

    /// A trip that's never been synced (`ownerUID == nil`) has no owner
    /// concept yet — this device is effectively it. Once synced, only the
    /// account that created it can delete it (see the Firestore `delete`
    /// rule on `trips/{tripId}`), so hide the action for everyone else
    /// rather than showing a control that silently fails remotely.
    private var isCurrentUserOwner: Bool {
        trip.ownerUID == nil || trip.ownerUID == authService.firebaseUser?.uid
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip") {
                    TextField("Trip Name", text: $name)
                    LocationSearchField(
                        placeholder: "Destination",
                        text: $location,
                        onSelect: { name, coordinate in
                            location = name
                            latitude = coordinate?.latitude
                            longitude = coordinate?.longitude
                        }
                    )
                }

                Section("Theme") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(TripTheme.allCases) { candidate in
                                Button {
                                    theme = candidate
                                } label: {
                                    Circle()
                                        .fill(candidate.accentColor)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(.primary, lineWidth: theme == candidate ? 2 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(candidate.displayName)
                                .accessibilityAddTraits(theme == candidate ? [.isSelected] : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Dates") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        .onChange(of: startDate) { _, newValue in
                            if newValue > endDate {
                                endDate = Calendar.current.date(byAdding: .day, value: 5, to: newValue) ?? newValue
                            }
                        }
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                }

                Section("Budget Currency") {
                    Picker("Currency", selection: $currency) {
                        ForEach(CurrencyCode.common, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                }

                Section("Description") {
                    TextField("Optional notes about this trip", text: $tripDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                if isCurrentUserOwner {
                    Section {
                        Button("Delete Trip", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .navigationTitle("Trip Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .confirmationDialog(
                "Delete this trip?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Trip", role: .destructive) {
                    onDeleted()
                }
            } message: {
                Text("This removes all activities, accommodations, budget, preparation, transport, and notes for this trip. This can't be undone.")
            }
        }
        .confirmsDiscard(isPresented: $isConfirmingDiscard, onDiscard: { dismiss() })
    }

    private func save() {
        trip.name = name.trimmingCharacters(in: .whitespaces)
        trip.location = location.trimmingCharacters(in: .whitespaces)
        trip.latitude = latitude
        trip.longitude = longitude
        trip.theme = theme
        trip.startDate = startDate
        trip.endDate = endDate
        trip.currency = currency
        trip.tripDescription = tripDescription
        trip.updatedAt = .now
        if trip.ownerUID != nil {
            let tripID = trip.id
            let updatedName = trip.name
            let updatedLocation = trip.location
            let updatedTheme = trip.theme.rawValue
            let updatedStart = trip.startDate
            let updatedEnd = trip.endDate
            let updatedBudget = trip.overallBudget
            let updatedCurrency = trip.currency
            let updatedDescription = trip.tripDescription
            let updatedLatitude = trip.latitude
            let updatedLongitude = trip.longitude
            let updatedMemberBudgets = trip.memberBudgets
            Task {
                try? await TripMembershipService.updateTripRecord(
                    tripID: tripID, name: updatedName, location: updatedLocation,
                    theme: updatedTheme, startDate: updatedStart, endDate: updatedEnd,
                    overallBudget: updatedBudget, currency: updatedCurrency, tripDescription: updatedDescription,
                    latitude: updatedLatitude, longitude: updatedLongitude, memberBudgets: updatedMemberBudgets
                )
            }
        }
        dismiss()
    }
}
