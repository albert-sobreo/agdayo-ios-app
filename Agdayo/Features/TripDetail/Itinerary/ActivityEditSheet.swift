import SwiftUI
import SwiftData
import MapKit
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

    /// How a new activity's place is chosen: typing a name, or tapping a place on a map.
    private enum EntryMode: String, CaseIterable, Identifiable {
        case type = "Type"
        case map = "Map"
        var id: String { rawValue }
    }

    @State private var entryMode: EntryMode = .type
    @State private var camera: MapCameraPosition
    @State private var mapSelection: MapSelection<UUID>?
    @State private var isResolvingPlace = false
    @State private var mapSearchText = ""
    /// The title last filled in from a map pick, so picking another place can
    /// replace it without overwriting a title the person typed themselves.
    @State private var autoFilledTitle: String?
    /// Activities added so far with "Add & Next" in this sitting.
    @State private var addedCount = 0
    @State private var scrollPosition = ScrollPosition(edge: .top)

    /// Live query so the map's pins and the next default time include
    /// activities added a moment ago (see `ItineraryTimelineView`'s `@Query`).
    @Query private var tripActivities: [Activity]

    init(trip: Trip, editingActivity: Activity? = nil, memberProfiles: [AppUserProfile] = [], latestActivityDate: Date? = nil) {
        self.trip = trip
        self.editingActivity = editingActivity
        self.memberProfiles = memberProfiles
        let tripID = trip.id
        _tripActivities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID })
        if let center = trip.coordinate {
            _camera = State(initialValue: .region(MKCoordinateRegion(center: center, latitudinalMeters: 8000, longitudinalMeters: 8000)))
        } else {
            _camera = State(initialValue: .automatic)
        }
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
            .scrollPosition($scrollPosition)
            .scrollDismissesKeyboard(.interactively)
            .brandForm(accent: trip.theme.accentColor)
            .safeAreaInset(edge: .top, spacing: 0) {
                if isAdding {
                    VStack(spacing: 0) {
                        modePicker
                        if isMapMode { mapPicker }
                    }
                    .background(BrandPalette.canvas)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isMapMode { mapActionBar }
            }
            .navigationTitle(editingActivity == nil ? "Add Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                }
                // In map mode the bottom bar has the Add buttons instead.
                if !isMapMode {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(!isValid)
                    }
                }
            }
            .onChange(of: mapSelection) { _, selection in
                guard let feature = selection?.feature else { return }
                Task { await choose(feature) }
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

    private var isAdding: Bool { editingActivity == nil }
    private var isMapMode: Bool { isAdding && entryMode == .map }

    private var modePicker: some View {
        Picker("Choose place by", selection: $entryMode) {
            ForEach(EntryMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// A plain map: tap any named place on it (restaurant, landmark, beach…),
    /// or search for one, to fill in the title, location and coordinates below.
    /// Only the place you choose is marked.
    private var mapPicker: some View {
        Map(position: $camera, selection: $mapSelection) {
            if let latitude, let longitude {
                Marker(title.isEmpty ? location : title, systemImage: iconName, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                    .tint(trip.theme.accentColor)
            }
        }
        .containerRelativeFrame(.vertical) { height, _ in height * 0.34 }
        .overlay(alignment: .top) {
            LocationSearchField(
                placeholder: "Search or tap a place on the map",
                text: $mapSearchText,
                regionBiasCenter: trip.coordinate,
                onSelect: { name, coordinate in
                    applyPlace(name: name, coordinate: coordinate)
                    if let coordinate {
                        camera = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 1500, longitudinalMeters: 1500))
                    }
                }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
            if isResolvingPlace {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
                    .padding(8)
            }
        }
    }

    /// Add & Next saves this activity and clears the form for the next one;
    /// Add saves and closes. Once something has been added, Add becomes Done.
    private var mapActionBar: some View {
        VStack(spacing: 8) {
            if addedCount > 0 {
                Text(addedCount == 1 ? "1 activity added" : "\(addedCount) activities added")
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Button("Add & Next", action: addAndNext)
                    .buttonStyle(.appSecondary)
                    .disabled(!isValid)
                Button(isValid || addedCount == 0 ? "Add" : "Done") {
                    if isValid { save() } else { dismiss() }
                }
                .buttonStyle(.appPrimary)
                .disabled(!isValid && addedCount == 0)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    /// Fills in the form from a tapped map place.
    private func choose(_ feature: MapFeature) async {
        isResolvingPlace = true
        defer { isResolvingPlace = false }
        guard let item = try? await MKMapItemRequest(feature: feature).mapItem,
              let name = item.name, !name.isEmpty else { return }
        applyPlace(name: name, coordinate: item.placemark.coordinate)
        mapSearchText = name
    }

    /// Shared by tapping a place and picking a search result.
    private func applyPlace(name: String, coordinate: CLLocationCoordinate2D?) {
        location = name
        latitude = coordinate?.latitude
        longitude = coordinate?.longitude
        if title.trimmingCharacters(in: .whitespaces).isEmpty || title == autoFilledTitle {
            title = name
            autoFilledTitle = name
        }
    }

    private func addAndNext() {
        guard isValid else { return }
        let saved = persist()
        addedCount += 1
        // Start the next one an hour after whichever is latest, including the one just saved.
        let latest = (tripActivities.map(\.date) + [saved.date]).max()
        title = ""
        autoFilledTitle = nil
        location = ""
        latitude = nil
        longitude = nil
        costText = ""
        costNote = ""
        exchangeRate = nil
        activityDescription = ""
        iconName = "mappin.and.ellipse"
        budgetCategoryID = nil
        budgetMemberUID = nil
        splitAmounts = [:]
        date = Self.defaultNewDate(for: trip, after: latest)
        mapSelection = nil
        mapSearchText = ""
        scrollPosition.scrollTo(edge: .top)
        // What's saved is no longer an unsaved change for Cancel's discard prompt.
        initialSignature = signature
    }

    private func save() {
        _ = persist()
        dismiss()
    }

    /// Inserts or updates the activity, syncs it and schedules its reminder.
    @discardableResult
    private func persist() -> Activity {
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
        return activity
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
