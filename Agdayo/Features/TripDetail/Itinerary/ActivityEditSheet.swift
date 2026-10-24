import SwiftUI
import SwiftData
import FirebaseAuth

struct ActivityEditSheet: View {
    let trip: Trip
    var editingActivity: Activity?
    var memberProfiles: [AppUserProfile] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService

    @State private var title: String
    @State private var location: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var date: Date
    @State private var costText: String
    @State private var costCurrency: String
    @State private var costNote: String
    @State private var exchangeRate: Double?
    @State private var activityDescription: String
    @State private var iconName: String
    @State private var budgetCategoryID: UUID?
    @State private var budgetMemberUID: String?
    @State private var paidByUID: String?
    @State private var splitUIDs: Set<String>
    @State private var splitAmounts: [String: Double]

    init(trip: Trip, editingActivity: Activity? = nil, memberProfiles: [AppUserProfile] = [], latestActivityDate: Date? = nil) {
        self.trip = trip
        self.editingActivity = editingActivity
        self.memberProfiles = memberProfiles
        _title = State(initialValue: editingActivity?.title ?? "")
        _location = State(initialValue: editingActivity?.location ?? "")
        _latitude = State(initialValue: editingActivity?.latitude)
        _longitude = State(initialValue: editingActivity?.longitude)
        _date = State(initialValue: editingActivity?.date ?? Self.defaultNewDate(for: trip, after: latestActivityDate))
        _costText = State(initialValue: editingActivity?.cost.map { String($0) } ?? "")
        _costCurrency = State(initialValue: editingActivity?.costCurrency ?? trip.currency)
        _costNote = State(initialValue: editingActivity?.costNote ?? "")
        _exchangeRate = State(initialValue: editingActivity?.exchangeRateToTripCurrency)
        _activityDescription = State(initialValue: editingActivity?.activityDescription ?? "")
        _iconName = State(initialValue: editingActivity?.iconName ?? "mappin.and.ellipse")
        _budgetCategoryID = State(initialValue: editingActivity?.budgetCategoryID)
        _budgetMemberUID = State(initialValue: editingActivity?.budgetMemberUID)
        _paidByUID = State(initialValue: editingActivity?.paidByUID)
        if let editingActivity, !editingActivity.splitUIDs.isEmpty {
            _splitUIDs = State(initialValue: Set(editingActivity.splitUIDs))
        } else {
            _splitUIDs = State(initialValue: Set(memberProfiles.map(\.uid)))
        }
        _splitAmounts = State(initialValue: editingActivity?.splitAmounts ?? [:])
    }

    /// Gap between the previous activity's start and a new activity's default start.
    private static let defaultGap: TimeInterval = 60 * 60

    /// A new activity starts one hour after the trip's latest activity (passed
    /// in by the caller from a live query), on the same day unless that pushes
    /// past the trip's last day. Falls back to the trip's start date when there
    /// are no activities yet.
    private static func defaultNewDate(for trip: Trip, after latest: Date?) -> Date {
        guard let latest else { return trip.startDate }
        let next = latest.addingTimeInterval(defaultGap)
        let lastMoment = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: trip.endDate) ?? trip.endDate
        return min(next, lastMoment)
    }

    private var dateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: trip.endDate) ?? trip.endDate
        return trip.startDate...end
    }

    @State private var isConfirmingDiscard = false
    /// Every input as one string, captured when the sheet appears, so Cancel
    /// can tell whether anything changed.
    @State private var initialSignature: String?

    private var signature: String {
        let parts: [String] = [
            title,
            location,
            "\(date.timeIntervalSince1970)",
            costText,
            costCurrency,
            costNote,
            activityDescription,
            iconName,
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
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    FormCard(title: "Activity", icon: "mappin.and.ellipse", accent: trip.theme.accentColor) {
                        FormField("Title") {
                            TextField("Title", text: $title)
                        }
                        FormField("Location") {
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
                    }

                    FormCard(title: "When", icon: "clock", accent: trip.theme.accentColor) {
                        FormField {
                            DatePicker("Date & Time", selection: $date, in: dateRange, displayedComponents: [.date, .hourAndMinute])
                        }
                    }

                    FormCard(title: "Cost", icon: "wallet.pass", accent: trip.theme.accentColor) {
                        FormField("Amount") {
                            TextField("Optional", text: $costText)
                                .keyboardType(.decimalPad)
                        }
                        FormField {
                            Picker("Currency", selection: $costCurrency) {
                                ForEach(CurrencyCode.common, id: \.self) { code in
                                    Text(code).tag(code)
                                }
                            }
                            .onChange(of: costCurrency) { _, _ in exchangeRate = nil }
                        }
                        if costCurrency != trip.currency {
                            FormField {
                                ExchangeRateField(amount: Double(costText) ?? 0, fromCurrency: costCurrency, toCurrency: trip.currency, rate: $exchangeRate)
                            }
                        }
                        FormField("Note") {
                            TextField("e.g. \"Included\"", text: $costNote)
                        }
                        FormField {
                            BudgetCategoryPicker(categories: trip.budgetCategories, memberProfiles: memberProfiles, categoryID: $budgetCategoryID, memberUID: $budgetMemberUID)
                        }
                    }

                    FormCard(title: "Icon", icon: "square.grid.2x2", accent: trip.theme.accentColor) {
                        IconPickerGrid(selectedIcon: $iconName, accentColor: trip.theme.accentColor)
                            .frame(height: 260)
                    }

                    FormCard(title: "Description", icon: "text.alignleft", accent: trip.theme.accentColor) {
                        FormField {
                            TextField("Optional details", text: $activityDescription, axis: .vertical)
                                .lineLimit(3...6)
                        }
                    }

                    ExpenseSplitSection(
                        memberProfiles: memberProfiles,
                        totalCost: Double(costText) ?? 0,
                        currencyCode: costCurrency,
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
            .navigationTitle(editingActivity == nil ? "Add Activity" : "Edit Activity")
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
            if editingActivity == nil, paidByUID == nil {
                paidByUID = authService.firebaseUser?.uid
            }
            if initialSignature == nil { initialSignature = signature }
        }
    }

    private func save() {
        let cost = Double(costText)
        let rate = costCurrency == trip.currency ? nil : exchangeRate
        let activity: Activity
        if let editingActivity {
            activity = editingActivity
            activity.title = title.trimmingCharacters(in: .whitespaces)
            activity.location = location
            activity.latitude = latitude
            activity.longitude = longitude
            activity.date = date
            activity.cost = cost
            activity.costCurrency = cost == nil ? nil : costCurrency
            activity.costNote = costNote
            activity.exchangeRateToTripCurrency = rate
            activity.activityDescription = activityDescription
            activity.iconName = iconName
            activity.budgetCategoryID = budgetCategoryID
            activity.budgetMemberUID = budgetMemberUID
            activity.paidByUID = paidByUID
            activity.splitUIDs = Array(splitUIDs)
            activity.splitAmounts = splitAmounts
        } else {
            activity = Activity(
                title: title.trimmingCharacters(in: .whitespaces),
                activityDescription: activityDescription,
                location: location,
                latitude: latitude,
                longitude: longitude,
                date: date,
                cost: cost,
                costCurrency: cost == nil ? nil : costCurrency,
                costNote: costNote,
                exchangeRateToTripCurrency: rate,
                iconName: iconName,
                budgetCategoryID: budgetCategoryID,
                budgetMemberUID: budgetMemberUID,
                paidByUID: paidByUID,
                splitUIDs: Array(splitUIDs),
                splitAmounts: splitAmounts,
                trip: trip
            )
            modelContext.insert(activity)
        }
        pushIfShared(activity)
        NotificationScheduler.scheduleReminder(for: activity)
        dismiss()
    }

    private func pushIfShared(_ activity: Activity) {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let activityID = activity.id
        let dto = activity.dto
        Task {
            try? await FirestoreCollectionSync.push(tripID: tripID, collection: "activities", docID: activityID, data: dto)
        }
    }
}
