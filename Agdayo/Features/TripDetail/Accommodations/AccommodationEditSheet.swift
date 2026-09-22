import SwiftUI
import SwiftData

struct AccommodationEditSheet: View {
    let trip: Trip
    var editingAccommodation: Accommodation?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var type: AccommodationType
    @State private var location: String
    @State private var numberOfRooms: Int
    @State private var totalCostText: String
    @State private var checkInTime: Date
    @State private var checkOutTime: Date
    @State private var startDate: Date
    @State private var endDate: Date

    init(trip: Trip, editingAccommodation: Accommodation? = nil) {
        self.trip = trip
        self.editingAccommodation = editingAccommodation
        _name = State(initialValue: editingAccommodation?.name ?? "")
        _type = State(initialValue: editingAccommodation?.type ?? .hotel)
        _location = State(initialValue: editingAccommodation?.location ?? "")
        _numberOfRooms = State(initialValue: editingAccommodation?.numberOfRooms ?? 1)
        _totalCostText = State(initialValue: editingAccommodation.map { String($0.totalCost) } ?? "")
        _checkInTime = State(initialValue: Self.time(from: editingAccommodation?.checkInTime ?? "15:00"))
        _checkOutTime = State(initialValue: Self.time(from: editingAccommodation?.checkOutTime ?? "11:00"))
        _startDate = State(initialValue: editingAccommodation?.startDate ?? trip.startDate)
        _endDate = State(initialValue: editingAccommodation?.endDate ?? trip.endDate)
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && startDate <= endDate
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Accommodation") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(AccommodationType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    LocationSearchField(placeholder: "Location", text: $location, onSelect: { name, _ in location = name })
                    Stepper("Rooms: \(numberOfRooms)", value: $numberOfRooms, in: 1...20)
                }

                Section("Dates") {
                    DatePicker("Check-in Date", selection: $startDate, in: trip.startDate...trip.endDate, displayedComponents: .date)
                    DatePicker("Check-in Time", selection: $checkInTime, displayedComponents: .hourAndMinute)
                    DatePicker("Check-out Date", selection: $endDate, in: startDate...trip.endDate, displayedComponents: .date)
                    DatePicker("Check-out Time", selection: $checkOutTime, displayedComponents: .hourAndMinute)
                }

                Section("Cost") {
                    TextField("Total Cost", text: $totalCostText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(editingAccommodation == nil ? "Add Accommodation" : "Edit Accommodation")
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
        let checkIn = Self.timeString(from: checkInTime)
        let checkOut = Self.timeString(from: checkOutTime)
        if let accommodation = editingAccommodation {
            accommodation.name = name.trimmingCharacters(in: .whitespaces)
            accommodation.type = type
            accommodation.location = location
            accommodation.numberOfRooms = numberOfRooms
            accommodation.totalCost = Double(totalCostText) ?? 0
            accommodation.checkInTime = checkIn
            accommodation.checkOutTime = checkOut
            accommodation.startDate = startDate
            accommodation.endDate = endDate
        } else {
            let accommodation = Accommodation(
                name: name.trimmingCharacters(in: .whitespaces),
                type: type,
                location: location,
                numberOfRooms: numberOfRooms,
                totalCost: Double(totalCostText) ?? 0,
                checkInTime: checkIn,
                checkOutTime: checkOut,
                startDate: startDate,
                endDate: endDate,
                trip: trip
            )
            modelContext.insert(accommodation)
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
