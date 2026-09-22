import SwiftUI
import SwiftData

struct TransportSegmentEditSheet: View {
    let trip: Trip
    var editingSegment: TransportSegment?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
    @State private var notes: String

    init(trip: Trip, editingSegment: TransportSegment? = nil) {
        self.trip = trip
        self.editingSegment = editingSegment
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
        _notes = State(initialValue: editingSegment?.notes ?? "")
    }

    private var isValid: Bool {
        !departureLocation.trimmingCharacters(in: .whitespaces).isEmpty
            && !arrivalLocation.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mode") {
                    Picker("Mode", selection: $mode) {
                        ForEach(TransportMode.allCases) { mode in
                            Label(mode.displayName, systemImage: mode.iconName).tag(mode)
                        }
                    }
                }

                Section("Departure") {
                    LocationSearchField(placeholder: "Departure Location", text: $departureLocation, onSelect: { name, _ in departureLocation = name })
                    DatePicker("Departure", selection: $departureDateTime, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Arrival") {
                    LocationSearchField(placeholder: "Arrival Location", text: $arrivalLocation, onSelect: { name, _ in arrivalLocation = name })
                    Toggle("Add arrival date/time", isOn: $hasArrivalDetails)
                    if hasArrivalDetails {
                        DatePicker("Arrival", selection: $arrivalDateTime, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section("Booking") {
                    TextField("Booking Reference (optional)", text: $bookingRef)
                    TextField("Seat Number (optional)", text: $seatNumber)
                }

                Section("Cost") {
                    TextField("Cost", text: $costText)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        ForEach(CurrencyCode.common, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
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
    }

    private func save() {
        let calendar = Calendar.current
        let departureDate = calendar.startOfDay(for: departureDateTime)
        let departureTime = Self.timeString(from: departureDateTime)
        let arrivalDate: Date? = hasArrivalDetails ? calendar.startOfDay(for: arrivalDateTime) : nil
        let arrivalTime: String? = hasArrivalDetails ? Self.timeString(from: arrivalDateTime) : nil
        let cost = Double(costText) ?? 0

        if let segment = editingSegment {
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
            segment.notes = notes.isEmpty ? nil : notes
        } else {
            let segment = TransportSegment(
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
                notes: notes.isEmpty ? nil : notes,
                trip: trip
            )
            modelContext.insert(segment)
        }
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
