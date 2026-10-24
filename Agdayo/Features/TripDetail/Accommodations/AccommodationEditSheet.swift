import SwiftUI
import SwiftData
import FirebaseAuth

struct AccommodationEditSheet: View {
    let trip: Trip
    var editingAccommodation: Accommodation?
    var memberProfiles: [AppUserProfile] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService

    @State private var name: String
    @State private var type: AccommodationType
    @State private var location: String
    @State private var numberOfRooms: Int
    @State private var totalCostText: String
    @State private var budgetCategoryID: UUID?
    @State private var budgetMemberUID: String?
    @State private var checkInTime: Date
    @State private var checkOutTime: Date
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var paidByUID: String?
    @State private var splitUIDs: Set<String>
    @State private var splitAmounts: [String: Double]

    init(trip: Trip, editingAccommodation: Accommodation? = nil, memberProfiles: [AppUserProfile] = []) {
        self.trip = trip
        self.editingAccommodation = editingAccommodation
        self.memberProfiles = memberProfiles
        _name = State(initialValue: editingAccommodation?.name ?? "")
        _type = State(initialValue: editingAccommodation?.type ?? .hotel)
        _location = State(initialValue: editingAccommodation?.location ?? "")
        _numberOfRooms = State(initialValue: editingAccommodation?.numberOfRooms ?? 1)
        _totalCostText = State(initialValue: editingAccommodation.map { String($0.totalCost) } ?? "")
        _budgetCategoryID = State(initialValue: editingAccommodation?.budgetCategoryID)
        _budgetMemberUID = State(initialValue: editingAccommodation?.budgetMemberUID)
        _checkInTime = State(initialValue: Self.time(from: editingAccommodation?.checkInTime ?? "15:00"))
        _checkOutTime = State(initialValue: Self.time(from: editingAccommodation?.checkOutTime ?? "11:00"))
        _startDate = State(initialValue: editingAccommodation?.startDate ?? trip.startDate)
        _endDate = State(initialValue: editingAccommodation?.endDate ?? trip.endDate)
        _paidByUID = State(initialValue: editingAccommodation?.paidByUID)
        if let editingAccommodation, !editingAccommodation.splitUIDs.isEmpty {
            _splitUIDs = State(initialValue: Set(editingAccommodation.splitUIDs))
        } else {
            _splitUIDs = State(initialValue: Set(memberProfiles.map(\.uid)))
        }
        _splitAmounts = State(initialValue: editingAccommodation?.splitAmounts ?? [:])
    }

    @State private var isConfirmingDiscard = false
    /// Every input as one string, captured when the sheet appears, so Cancel
    /// can tell whether anything changed.
    @State private var initialSignature: String?

    private var signature: String {
        let parts: [String] = [
            name,
            type.rawValue,
            location,
            "\(numberOfRooms)",
            totalCostText,
            "\(startDate.timeIntervalSince1970)",
            "\(endDate.timeIntervalSince1970)",
            "\(checkInTime.timeIntervalSince1970)",
            "\(checkOutTime.timeIntervalSince1970)",
            (budgetCategoryID?.uuidString ?? ""),
            (budgetMemberUID ?? ""),
            (paidByUID ?? ""),
            splitUIDs.sorted().joined(separator: ","),
            splitAmounts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        ]
        return parts.joined(separator: "|")
    }

    private var hasChanges: Bool {
        initialSignature != nil && signature != initialSignature
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && startDate <= endDate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    FormCard(title: "Accommodation", icon: "bed.double", accent: trip.theme.accentColor) {
                        FormField("Name") {
                            TextField("Name", text: $name)
                        }
                        FormField {
                            Picker("Type", selection: $type) {
                                ForEach(AccommodationType.allCases) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                        }
                        FormField("Location") {
                            LocationSearchField(placeholder: "Location", text: $location, onSelect: { name, _ in location = name })
                        }
                        FormField {
                            Stepper("Rooms: \(numberOfRooms)", value: $numberOfRooms, in: 1...20)
                        }
                    }

                    FormCard(title: "Dates", icon: "calendar", accent: trip.theme.accentColor) {
                        FormField {
                            DatePicker("Check-in Date", selection: $startDate, in: trip.startDate...trip.endDate, displayedComponents: .date)
                        }
                        FormField {
                            DatePicker("Check-in Time", selection: $checkInTime, displayedComponents: .hourAndMinute)
                        }
                        FormField {
                            DatePicker("Check-out Date", selection: $endDate, in: startDate...trip.endDate, displayedComponents: .date)
                        }
                        FormField {
                            DatePicker("Check-out Time", selection: $checkOutTime, displayedComponents: .hourAndMinute)
                        }
                    }

                    FormCard(title: "Cost", icon: "wallet.pass", accent: trip.theme.accentColor) {
                        FormField("Total cost") {
                            TextField("Total Cost", text: $totalCostText)
                                .keyboardType(.decimalPad)
                        }
                        FormField {
                            BudgetCategoryPicker(categories: trip.budgetCategories, memberProfiles: memberProfiles, categoryID: $budgetCategoryID, memberUID: $budgetMemberUID)
                        }
                    }

                    ExpenseSplitSection(
                        memberProfiles: memberProfiles,
                        totalCost: Double(totalCostText) ?? 0,
                        currencyCode: trip.currency,
                        accentColor: trip.theme.accentColor,
                        paidByUID: $paidByUID,
                        splitUIDs: $splitUIDs,
                        splitAmounts: $splitAmounts
                    )
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .brandForm(accent: trip.theme.accentColor)
            .navigationTitle(editingAccommodation == nil ? "Add Accommodation" : "Edit Accommodation")
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
        }
        .confirmsDiscard(isPresented: $isConfirmingDiscard, onDiscard: { dismiss() })
        .onAppear {
            if editingAccommodation == nil, paidByUID == nil {
                paidByUID = authService.firebaseUser?.uid
            }
            if initialSignature == nil { initialSignature = signature }
        }
    }

    private func save() {
        let checkIn = Self.timeString(from: checkInTime)
        let checkOut = Self.timeString(from: checkOutTime)
        let accommodation: Accommodation
        if let editingAccommodation {
            accommodation = editingAccommodation
            accommodation.name = name.trimmingCharacters(in: .whitespaces)
            accommodation.type = type
            accommodation.location = location
            accommodation.numberOfRooms = numberOfRooms
            accommodation.totalCost = Double(totalCostText) ?? 0
            accommodation.budgetCategoryID = budgetCategoryID
            accommodation.budgetMemberUID = budgetMemberUID
            accommodation.checkInTime = checkIn
            accommodation.checkOutTime = checkOut
            accommodation.startDate = startDate
            accommodation.endDate = endDate
            accommodation.paidByUID = paidByUID
            accommodation.splitUIDs = Array(splitUIDs)
            accommodation.splitAmounts = splitAmounts
        } else {
            accommodation = Accommodation(
                name: name.trimmingCharacters(in: .whitespaces),
                type: type,
                location: location,
                numberOfRooms: numberOfRooms,
                totalCost: Double(totalCostText) ?? 0,
                checkInTime: checkIn,
                checkOutTime: checkOut,
                startDate: startDate,
                endDate: endDate,
                budgetCategoryID: budgetCategoryID,
                budgetMemberUID: budgetMemberUID,
                paidByUID: paidByUID,
                splitUIDs: Array(splitUIDs),
                splitAmounts: splitAmounts,
                trip: trip
            )
            modelContext.insert(accommodation)
        }
        if trip.ownerUID != nil {
            let tripID = trip.id
            let accommodationID = accommodation.id
            let dto = accommodation.dto
            Task {
                try? await FirestoreCollectionSync.push(tripID: tripID, collection: "accommodations", docID: accommodationID, data: dto)
            }
        }
        dismiss()
    }

    private static func time(from string: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: string) ?? .now
    }

    private static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
