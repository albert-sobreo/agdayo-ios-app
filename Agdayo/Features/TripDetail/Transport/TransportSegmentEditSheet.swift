import SwiftUI
import SwiftData
import FirebaseAuth

struct TransportSegmentEditSheet: View {
    let trip: Trip
    var editingSegment: TransportSegment?
    var memberProfiles: [AppUserProfile] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService

    @State private var mode: TransportMode
    @State private var departureLocation: String
    @State private var departureDateTime: Date
    @State private var arrivalLocation: String
    @State private var hasArrivalDetails: Bool
    @State private var arrivalDateTime: Date
    @State private var bookingRef: String
    @State private var seatNumber: String
    @State private var costText: String
    @State private var currency: String
    @State private var exchangeRate: Double?
    @State private var notes: String
    @State private var budgetCategoryID: UUID?
    @State private var budgetMemberUID: String?
    @State private var paidByUID: String?
    @State private var splitUIDs: Set<String>
    @State private var splitAmounts: [String: Double]

    init(trip: Trip, editingSegment: TransportSegment? = nil, memberProfiles: [AppUserProfile] = []) {
        self.trip = trip
        self.editingSegment = editingSegment
        self.memberProfiles = memberProfiles
        _mode = State(initialValue: editingSegment?.mode ?? .flight)
        _departureLocation = State(initialValue: editingSegment?.departureLocation ?? "")
        _departureDateTime = State(initialValue: Self.combine(date: editingSegment?.departureDate ?? trip.startDate, time: editingSegment?.departureTime ?? "09:00"))
        _arrivalLocation = State(initialValue: editingSegment?.arrivalLocation ?? "")
        _hasArrivalDetails = State(initialValue: editingSegment?.arrivalDate != nil)
        _arrivalDateTime = State(initialValue: Self.combine(date: editingSegment?.arrivalDate ?? trip.startDate, time: editingSegment?.arrivalTime ?? "12:00"))
        _bookingRef = State(initialValue: editingSegment?.bookingRef ?? "")
        _seatNumber = State(initialValue: editingSegment?.seatNumber ?? "")
        _costText = State(initialValue: editingSegment.map { String($0.cost) } ?? "")
        _currency = State(initialValue: editingSegment?.currency ?? trip.currency)
        _exchangeRate = State(initialValue: editingSegment?.exchangeRateToTripCurrency)
        _notes = State(initialValue: editingSegment?.notes ?? "")
        _budgetCategoryID = State(initialValue: editingSegment?.budgetCategoryID)
        _budgetMemberUID = State(initialValue: editingSegment?.budgetMemberUID)
        _paidByUID = State(initialValue: editingSegment?.paidByUID)
        if let editingSegment, !editingSegment.splitUIDs.isEmpty {
            _splitUIDs = State(initialValue: Set(editingSegment.splitUIDs))
        } else {
            _splitUIDs = State(initialValue: Set(memberProfiles.map(\.uid)))
        }
        _splitAmounts = State(initialValue: editingSegment?.splitAmounts ?? [:])
    }

    private var isValid: Bool {
        !departureLocation.trimmingCharacters(in: .whitespaces).isEmpty
            && !arrivalLocation.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    FormCard(title: "Mode", icon: "arrow.triangle.swap", accent: trip.theme.accentColor) {
                        FormField {
                            Picker("Mode", selection: $mode) {
                                ForEach(TransportMode.allCases) { mode in
                                    Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                                }
                            }
                        }
                    }

                    FormCard(title: "Departure", icon: "airplane.departure", accent: trip.theme.accentColor) {
                        FormField("Location") {
                            LocationSearchField(placeholder: "Departure Location", text: $departureLocation, onSelect: { name, _ in departureLocation = name })
                        }
                        FormField {
                            DatePicker("Departure", selection: $departureDateTime, displayedComponents: [.date, .hourAndMinute])
                        }
                    }

                    FormCard(title: "Arrival", icon: "airplane.arrival", accent: trip.theme.accentColor) {
                        FormField("Location") {
                            LocationSearchField(placeholder: "Arrival Location", text: $arrivalLocation, onSelect: { name, _ in arrivalLocation = name })
                        }
                        FormField {
                            Toggle("Add arrival date/time", isOn: $hasArrivalDetails)
                        }
                        if hasArrivalDetails {
                            FormField {
                                DatePicker("Arrival", selection: $arrivalDateTime, displayedComponents: [.date, .hourAndMinute])
                            }
                        }
                    }

                    FormCard(title: "Booking", icon: "ticket", accent: trip.theme.accentColor) {
                        FormField("Booking reference") {
                            TextField("Optional", text: $bookingRef)
                        }
                        FormField("Seat number") {
                            TextField("Optional", text: $seatNumber)
                        }
                    }

                    FormCard(title: "Cost", icon: "wallet.pass", accent: trip.theme.accentColor) {
                        FormField("Cost") {
                            TextField("Cost", text: $costText)
                                .keyboardType(.decimalPad)
                        }
                        FormField {
                            Picker("Currency", selection: $currency) {
                                ForEach(CurrencyCode.common, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .onChange(of: currency) { _, _ in exchangeRate = nil }
                        }
                        if currency != trip.currency {
                            FormField {
                                ExchangeRateField(amount: Double(costText) ?? 0, fromCurrency: currency, toCurrency: trip.currency, rate: $exchangeRate)
                            }
                        }
                        FormField {
                            BudgetCategoryPicker(categories: trip.budgetCategories, memberProfiles: memberProfiles, categoryID: $budgetCategoryID, memberUID: $budgetMemberUID)
                        }
                    }

                    FormCard(title: "Notes", icon: "note.text", accent: trip.theme.accentColor) {
                        FormField {
                            TextField("Optional notes", text: $notes, axis: .vertical)
                                .lineLimit(3...6)
                        }
                    }

                    ExpenseSplitSection(
                        memberProfiles: memberProfiles,
                        totalCost: Double(costText) ?? 0,
                        currencyCode: currency,
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
            .navigationTitle(editingSegment == nil ? "Add Transport" : "Edit Transport")
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
        .onAppear {
            if editingSegment == nil, paidByUID == nil {
                paidByUID = authService.firebaseUser?.uid
            }
        }
    }

    private func save() {
        let calendar = Calendar.current
        let departureDate = calendar.startOfDay(for: departureDateTime)
        let departureTime = Self.timeString(from: departureDateTime)
        let arrivalDate: Date? = hasArrivalDetails ? calendar.startOfDay(for: arrivalDateTime) : nil
        let arrivalTime: String? = hasArrivalDetails ? Self.timeString(from: arrivalDateTime) : nil
        let cost = Double(costText) ?? 0
        let rate = currency == trip.currency ? nil : exchangeRate

        let segment: TransportSegment
        if let editingSegment {
            segment = editingSegment
            segment.mode = mode
            segment.departureLocation = departureLocation
            segment.departureDate = departureDate
            segment.departureTime = departureTime
            segment.arrivalLocation = arrivalLocation
            segment.arrivalDate = arrivalDate
            segment.arrivalTime = arrivalTime
            segment.bookingRef = bookingRef.isEmpty ? nil : bookingRef
            segment.seatNumber = seatNumber.isEmpty ? nil : seatNumber
            segment.cost = cost
            segment.currency = currency
            segment.exchangeRateToTripCurrency = rate
            segment.notes = notes.isEmpty ? nil : notes
            segment.budgetCategoryID = budgetCategoryID
            segment.budgetMemberUID = budgetMemberUID
            segment.paidByUID = paidByUID
            segment.splitUIDs = Array(splitUIDs)
            segment.splitAmounts = splitAmounts
        } else {
            segment = TransportSegment(
                mode: mode,
                departureLocation: departureLocation,
                departureDate: departureDate,
                departureTime: departureTime,
                arrivalLocation: arrivalLocation,
                arrivalDate: arrivalDate,
                arrivalTime: arrivalTime,
                bookingRef: bookingRef.isEmpty ? nil : bookingRef,
                seatNumber: seatNumber.isEmpty ? nil : seatNumber,
                cost: cost,
                currency: currency,
                exchangeRateToTripCurrency: rate,
                notes: notes.isEmpty ? nil : notes,
                budgetCategoryID: budgetCategoryID,
                budgetMemberUID: budgetMemberUID,
                paidByUID: paidByUID,
                splitUIDs: Array(splitUIDs),
                splitAmounts: splitAmounts,
                trip: trip
            )
            modelContext.insert(segment)
        }
        if trip.ownerUID != nil {
            let tripID = trip.id
            let segmentID = segment.id
            let dto = segment.dto
            Task {
                try? await FirestoreCollectionSync.push(tripID: tripID, collection: "transportSegments", docID: segmentID, data: dto)
            }
        }
        NotificationScheduler.scheduleReminder(for: segment)
        dismiss()
    }

    private static func combine(date: Date, time: String) -> Date {
        let calendar = Calendar.current
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return date }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date) ?? date
    }

    private static func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
