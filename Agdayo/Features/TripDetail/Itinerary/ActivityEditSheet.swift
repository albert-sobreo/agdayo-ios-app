import SwiftUI
import SwiftData

struct ActivityEditSheet: View {
    let trip: Trip
    var editingActivity: Activity?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String
    @State private var location: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var date: Date
    @State private var costText: String
    @State private var costCurrency: String
    @State private var costNote: String
    @State private var activityDescription: String
    @State private var iconName: String

    init(trip: Trip, editingActivity: Activity? = nil) {
        self.trip = trip
        self.editingActivity = editingActivity
        _title = State(initialValue: editingActivity?.title ?? "")
        _location = State(initialValue: editingActivity?.location ?? "")
        _latitude = State(initialValue: editingActivity?.latitude)
        _longitude = State(initialValue: editingActivity?.longitude)
        _date = State(initialValue: editingActivity?.date ?? trip.startDate)
        _costText = State(initialValue: editingActivity?.cost.map { String($0) } ?? "")
        _costCurrency = State(initialValue: editingActivity?.costCurrency ?? trip.currency)
        _costNote = State(initialValue: editingActivity?.costNote ?? "")
        _activityDescription = State(initialValue: editingActivity?.activityDescription ?? "")
        _iconName = State(initialValue: editingActivity?.iconName ?? "mappin.and.ellipse")
    }

    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: trip.endDate) ?? trip.endDate
        return trip.startDate...end
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    TextField("Title", text: $title)
                    LocationSearchField(
                        placeholder: "Location",
                        text: $location,
                        onSelect: { name, coordinate in
                            location = name
                            latitude = coordinate?.latitude
                            longitude = coordinate?.longitude
                        }
                    )
                }

                Section("When") {
                    DatePicker("Date & Time", selection: $date, in: dateRange, displayedComponents: [.date, .hourAndMinute])
                }

                Section("Cost") {
                    TextField("Amount (optional)", text: $costText)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $costCurrency) {
                        ForEach(CurrencyCode.common, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    TextField("Note, e.g. \"Included\"", text: $costNote)
                }

                Section("Icon") {
                    IconPickerGrid(selectedIcon: $iconName, accentColor: trip.theme.accentColor)
                        .frame(height: 260)
                }

                Section("Description") {
                    TextField("Optional details", text: $activityDescription, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(editingActivity == nil ? "Add Activity" : "Edit Activity")
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
        let cost = Double(costText)
        if let activity = editingActivity {
            activity.title = title.trimmingCharacters(in: .whitespaces)
            activity.location = location
            activity.latitude = latitude
            activity.longitude = longitude
            activity.date = date
            activity.cost = cost
            activity.costCurrency = cost == nil ? nil : costCurrency
            activity.costNote = costNote
            activity.activityDescription = activityDescription
            activity.iconName = iconName
        } else {
            let activity = Activity(
                title: title.trimmingCharacters(in: .whitespaces),
                activityDescription: activityDescription,
                location: location,
                latitude: latitude,
                longitude: longitude,
                date: date,
                cost: cost,
                costCurrency: cost == nil ? nil : costCurrency,
                costNote: costNote,
                iconName: iconName,
                trip: trip
            )
            modelContext.insert(activity)
        }
        dismiss()
    }
}
