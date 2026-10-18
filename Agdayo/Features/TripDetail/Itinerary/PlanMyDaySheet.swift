import SwiftUI
import SwiftData
import MapKit
import Translation

/// "Plan my day": choose interests, pace and how far out to look, then walk
/// through the day one step at a time — breakfast, something to do, lunch…
/// — picking a place for each from nearby suggestions. Review the day, then
/// add it to the itinerary as regular activities.
struct PlanMyDaySheet: View {
    let trip: Trip

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @State private var model: PlanMyDayModel
    @State private var hasSeededInterests = false
    @State private var isPickingBase = false
    @State private var isConfirmingDiscard = false

    // Map interaction
    @State private var camera: MapCameraPosition = .automatic
    /// The row/marker the traveler is looking at (not necessarily selected).
    @State private var focusedID: UUID?
    @State private var mapSelection: UUID?
    @State private var detailItem: MKMapItem?

    /// English translations of names and places that aren't in English.
    @State private var translator = PlaceTranslator()

    // List focus: the destination's places first, other cities on demand.
    private let initialMainCount = 12
    @State private var showAllMain = false
    @State private var expandedCities: Set<String> = []

    /// - Parameter initialDay: The day to plan; when `nil` (opened from the
    ///   toolbar rather than an empty-day row) the first day with nothing
    ///   planned, falling back to the trip's first day.
    init(trip: Trip, initialDay: Date? = nil) {
        self.trip = trip
        let calendar = Calendar.current
        let day: Date
        if let initialDay {
            day = calendar.startOfDay(for: initialDay)
        } else {
            let used = Set(trip.activities.map { calendar.startOfDay(for: $0.date) })
            day = trip.calendarDays.first { !used.contains($0) } ?? calendar.startOfDay(for: trip.startDate)
        }
        _model = State(initialValue: PlanMyDayModel(trip: trip, day: day, interests: [.food, .culture]))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.phase {
                case .setup:
                    setupView
                case .loading:
                    loadingView
                case .stepping:
                    stepView
                case .review:
                    reviewView
                case .failed(let message):
                    EmptyStateView(
                        iconName: "mappin.slash",
                        title: "Couldn't Plan This Day",
                        message: message,
                        actionTitle: "Change Plan",
                        action: { model.backToSetup() }
                    )
                }
            }
            .navigationTitle("Plan My Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { requestClose() }
                }
            }
            // Swiping down must not throw away a half-planned day; closing goes
            // through Cancel, which asks first once there is something to lose.
            .interactiveDismissDisabled()
            .confirmationDialog("Discard this plan?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Plan", role: .destructive) { dismiss() }
                Button("Keep Planning", role: .cancel) {}
            } message: {
                Text("The places you picked won't be added to your itinerary.")
            }
            // Menus, buttons and pickers default to the app's accent color;
            // everything in here uses the trip's.
            .tint(trip.theme.accentColor)
            .onAppear {
                seedInterestsFromProfile()
                model.refreshBase()
            }
            .onChange(of: model.day) { model.refreshBase() }
            .onChange(of: model.currentStep) {
                camera = .automatic
                focusedID = nil
                showAllMain = false
                expandedCities = []
            }
            .onChange(of: mapSelection) { _, id in
                guard let id else { return }
                if let place = (model.suggestions + model.plannedStops.map(\.place)).first(where: { $0.id == id }) {
                    focus(place)
                    showDetails(for: place)
                }
                mapSelection = nil
            }
            .mapItemDetailSheet(item: $detailItem)
            .translationTask(translator.configuration) { session in
                await translator.translate(using: session)
            }
            .task(id: translationSignature) {
                translator.request(translationTexts)
            }
            .sheet(isPresented: $isPickingBase) {
                PlanBasePickerSheet(
                    accent: trip.theme.accentColor,
                    onPick: { model.setBase($0) },
                    onUseAutomatic: { model.resetBaseToAutomatic() }
                )
            }
        }
    }

    /// Closes straight away from the setup screen; otherwise confirms first,
    /// because the day isn't saved until "Add stops to day".
    private func requestClose() {
        if model.phase == .setup || (model.plannedStops.isEmpty && model.phase != .stepping && model.phase != .review) {
            dismiss()
        } else {
            isConfirmingDiscard = true
        }
    }

    // MARK: Setup

    private var setupView: some View {
        let accent = trip.theme.accentColor
        return ScrollView {
            VStack(spacing: 14) {
                setupCard("Day", icon: "calendar") {
                    Picker("Day", selection: $model.day) {
                        ForEach(Array(trip.calendarDays.enumerated()), id: \.element) { index, day in
                            Text("Day \(index + 1) · \(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                                .tag(day)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                setupCard("Where", icon: "mappin.and.ellipse") {
                    Button {
                        isPickingBase = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PLANNING AROUND")
                                    .font(AppFont.outfit(10, weight: .semibold, relativeTo: .caption2))
                                    .tracking(1.5)
                                    .foregroundStyle(accent)
                                if let base = model.base {
                                    Text(base.searchName)
                                        .font(AppFont.barlowCondensed(26, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(base.reason)
                                        .font(AppFont.outfit(12, relativeTo: .caption))
                                        .foregroundStyle(accent)
                                } else if model.isResolvingBase {
                                    Text("Finding where you'll be…")
                                        .font(AppFont.outfit(15, relativeTo: .body))
                                        .foregroundStyle(accent)
                                } else {
                                    Text("Choose a place")
                                        .font(AppFont.barlowCondensed(26, weight: .semibold))
                                        .foregroundStyle(.primary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text(model.base?.isBroad == true
                         ? "That's a large area. Pick a town or city to plan around for a tighter day."
                         : "Staying in another city, or heading out on a day trip? Change this to plan around that place.")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(accent)
                }

                setupCard("What are you into?", icon: "heart") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(Interest.allCases) { interest in
                            interestChip(interest)
                        }
                    }
                }

                setupCard("How busy?", icon: "gauge.with.dots.needle.50percent") {
                    Picker("Pace", selection: $model.pace) {
                        ForEach(Pace.allCases) { pace in
                            Text(pace.displayName).tag(pace)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("\(model.pace.steps.count) steps: \(model.pace.summary).")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }

                setupCard("How far out?", icon: "location.circle") {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        MoneyAmount(text: "\(Int(model.radiusKm))", size: 40, color: accent)
                        Text("km")
                            .font(AppFont.outfit(15, weight: .medium, relativeTo: .body))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.radiusKm, in: 1...30, step: 1)

                    Text("Places within this distance of \(model.base?.searchName ?? trip.location). Nearby cities are listed in their own sections.")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(BrandPalette.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await model.start() }
            } label: {
                Text("Start planning")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appPrimary)
            .padding()
            .background(.bar)
        }
    }

    /// One setup question as a card: a Budget-style header, then its controls.
    private func setupCard<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 12) {
                MoneySectionHeader(title: title, iconName: icon, accentColor: trip.theme.accentColor)
                content()
            }
        }
    }

    private func interestChip(_ interest: Interest) -> some View {
        let isSelected = model.interests.contains(interest)
        return Button {
            if isSelected {
                model.interests.remove(interest)
            } else {
                model.interests.insert(interest)
            }
        } label: {
            Label(interest.displayName, systemImage: interest.iconName)
                .font(AppFont.outfit(13, weight: .semibold, relativeTo: .footnote))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(isSelected ? .white : trip.theme.accentColor)
                .background(
                    isSelected ? trip.theme.accentColor : trip.theme.accentColor.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            ShimmerText(
                text: "Finding places around \(model.base?.searchName ?? trip.location)…",
                font: AppFont.outfit(15, weight: .semibold, relativeTo: .body)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Steps

    /// Split layout: the map on top (suggestions and the day so far), the
    /// step's time, filters and list below.
    private var stepView: some View {
        VStack(spacing: 0) {
            stepMap
                .containerRelativeFrame(.vertical) { height, _ in height * 0.3 }

            stepHeader

            PlanSearchField(
                prompt: "Search for a specific place",
                text: $model.searchText,
                isSearching: model.isSearching,
                accent: trip.theme.accentColor,
                onSearch: { model.runSearch() },
                onClear: { model.clearSearch() }
            )
            .padding(.horizontal)
            .padding(.vertical, 4)

            kindFilter

            Label("Suggestions come from Apple Maps. Always verify a place is open and still exists before you go.", systemImage: "exclamationmark.circle")
                .font(AppFont.outfit(12, relativeTo: .caption))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 4)

            List {
                ForEach(Array(model.cityGroups.enumerated()), id: \.element.id) { index, group in
                    let isSearch = group.id == "search"
                    let isCollapsible = !group.isLead && !isSearch
                    let isExpanded = expandedCities.contains(group.id)
                    let visible = visiblePlaces(in: group)

                    Section {
                        ForEach(visible) { candidate in
                            suggestionRow(candidate)
                        }
                    } header: {
                        HStack(spacing: 8) {
                            Text(english(for: group.name).map { "\(group.name) · \($0)" } ?? group.name)
                                .font(AppFont.outfit(13, weight: .semibold, relativeTo: .footnote))
                                .textCase(.uppercase)
                                .lineLimit(1)
                                .foregroundStyle(group.isLead ? trip.theme.accentColor : Color.secondary)
                            if group.isMain {
                                Text("Your destination")
                                    .font(AppFont.outfit(10, weight: .semibold, relativeTo: .caption2))
                                    .textCase(nil)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(.white)
                                    .background(trip.theme.accentColor, in: Capsule())
                            }
                            Text("\(group.places.count)")
                                .font(AppFont.outfit(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if index == 0 {
                                Menu {
                                    Picker("Sort", selection: $model.sort) {
                                        ForEach(StepSort.allCases) { sort in
                                            Text(sort.title).tag(sort)
                                        }
                                    }
                                } label: {
                                    Label(model.sort.title, systemImage: "arrow.up.arrow.down")
                                        .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                                        .textCase(nil)
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                            }
                            if isCollapsible {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard isCollapsible else { return }
                            withAnimation {
                                if isExpanded { expandedCities.remove(group.id) } else { expandedCities.insert(group.id) }
                            }
                        }
                    } footer: {
                        if group.isLead && !isSearch && !showAllMain && group.places.count > initialMainCount {
                            Button("Show \(group.places.count - initialMainCount) more in \(group.name)") {
                                withAnimation { showAllMain = true }
                            }
                            .font(AppFont.outfit(13, weight: .semibold, relativeTo: .footnote))
                        }
                    }
                }

                if model.suggestions.isEmpty {
                    Section {
                        Text(model.isLoadingStep ? "Finding places…" : model.isSearching ? "Searching…" : "Nothing here. Try another filter, a wider area, or search for a specific place above.")
                            .font(AppFont.outfit(13, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onChange(of: model.searchText) {
            if model.searchText.isEmpty { model.clearSearch() }
        }
        .safeAreaInset(edge: .bottom) { stepActions }
    }

    private var stepHeader: some View {
        let index = model.currentStep
        let kind = model.currentKind
        return VStack(spacing: 8) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("STEP \(index + 1) OF \(model.steps.count)")
                        .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    Label(kind?.title ?? "", systemImage: kind?.iconName ?? "mappin")
                        .font(AppFont.barlowCondensed(26, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(trip.theme.accentColor)
                }
                Spacer()
                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { model.timeDate(for: model.currentStep) },
                        set: { model.setTime($0, for: model.currentStep) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }

            ProgressView(value: Double(index), total: Double(max(model.steps.count, 1)))
                .tint(trip.theme.accentColor)
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var kindFilter: some View {
        let kinds = model.availableKinds
        if kinds.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kinds, id: \.self) { kind in
                        let isOn = model.enabledKinds.contains(kind)
                        Button {
                            model.toggleKind(kind)
                        } label: {
                            Text(kind.displayName)
                                .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(isOn ? .white : trip.theme.accentColor)
                                .background(
                                    isOn ? trip.theme.accentColor : trip.theme.accentColor.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
        }
    }

    private func suggestionRow(_ candidate: Candidate) -> some View {
        let isSelected = model.selectedID == candidate.id
        let isFocused = focusedID == candidate.id
        return HStack(spacing: 12) {
            // Tapping the place itself zooms the map to it; picking it is the
            // separate circle on the right.
            Button {
                focus(candidate)
            } label: {
                HStack(spacing: 12) {
                Image(systemName: candidate.kind.activityIconName)
                    .foregroundStyle(trip.theme.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(.black)
                    if let translated = english(for: candidate.name) {
                        Label(translated, systemImage: "globe")
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.black)
                    }
                    Text(subtitle(for: candidate))
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.black)
                }
                Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            // Borderless, like the two buttons beside it, so a tap lands on
            // exactly one of them and never on the select circle.
            .buttonStyle(.borderless)

            Button {
                showDetails(for: candidate)
            } label: {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(trip.theme.accentColor)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Details for \(candidate.name)")

            Button {
                model.selectedID = isSelected ? nil : candidate.id
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? trip.theme.accentColor : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isSelected ? "Selected" : "Select \(candidate.name)")
        }
        .listRowBackground(isFocused ? trip.theme.accentColor.opacity(0.1) : nil)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The places of a city group that are currently shown in the list:
    /// the destination's first few, other cities only once expanded.
    private func visiblePlaces(in group: PlanMyDayModel.CityGroup) -> [Candidate] {
        if group.id == "search" { return group.places }
        if group.isLead { return showAllMain ? group.places : Array(group.places.prefix(initialMainCount)) }
        return expandedCities.contains(group.id) ? group.places : []
    }

    /// Everything the list shows right now (the map plots the same places).
    private var visibleSuggestions: [Candidate] {
        model.cityGroups.flatMap(visiblePlaces(in:))
    }

    // MARK: Translation

    /// Every name, address and city currently on screen, so non-English ones
    /// get an English translation.
    private var translationTexts: [String] {
        var texts: [String] = []
        for candidate in visibleSuggestions {
            texts.append(candidate.name)
            if let locality = candidate.locality { texts.append(locality) }
        }
        for group in model.cityGroups where group.id != "search" { texts.append(group.name) }
        for item in model.plannedStops { texts.append(item.place.name) }
        return texts
    }

    private var translationSignature: Int {
        translationTexts.reduce(into: Hasher()) { $0.combine($1) }.finalize()
    }

    /// The English line shown under a name, or nil when there's nothing to add.
    private func english(for text: String?) -> String? {
        translator.translation(of: text)
    }

    // MARK: Map actions

    /// Zooms the step map to a place and highlights it.
    private func focus(_ candidate: Candidate) {
        focusedID = candidate.id
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(
                center: candidate.coordinate, latitudinalMeters: 700, longitudinalMeters: 700
            ))
        }
    }

    private func resetMapView() {
        focusedID = nil
        withAnimation(.easeInOut(duration: 0.4)) { camera = .automatic }
    }

    /// Opens Apple's own place card (hours, phone, photos…) for a place.
    private func showDetails(for candidate: Candidate) {
        Task { detailItem = await PlaceSearchService.mapItem(for: candidate) }
    }

    private func subtitle(for candidate: Candidate) -> String {
        var parts = [candidate.kind.displayName]
        if let locality = candidate.locality {
            parts.append(english(for: locality).map { "\(locality) (\($0))" } ?? locality)
        }
        if let meters = model.distanceFromReference(candidate) {
            let formatter = MKDistanceFormatter()
            formatter.unitStyle = .abbreviated
            parts.append("\(formatter.string(fromDistance: meters)) from \(model.referenceName)")
        }
        return parts.joined(separator: " · ")
    }

    private var stepActions: some View {
        HStack(spacing: 12) {
            Button {
                model.previousStep()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 24)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Back")

            Button("Skip") { model.skipStep() }
                .buttonStyle(.bordered)

            Button {
                model.confirmSelection()
            } label: {
                Text(confirmTitle)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appPrimary)
            .disabled(model.selectedCandidate == nil)
        }
        .padding()
        .background(.bar)
    }

    private var confirmTitle: String {
        guard let selected = model.selectedCandidate else { return "Pick a place" }
        let isLast = model.currentStep == model.steps.count - 1
        return isLast ? "Confirm \(selected.name)" : "Confirm & continue"
    }

    // MARK: Map

    /// Markers + a dashed line through the day so far. Markers are plain
    /// `Marker`s with a `.tag` (no nested Buttons — that combination froze the
    /// Map tab earlier); tapping one opens the place card.
    private var stepMap: some View {
        let chosen = model.plannedStops
        let suggestions = visibleSuggestions
        return Map(position: $camera, selection: $mapSelection) {
            ForEach(suggestions) { candidate in
                Marker(
                    candidate.name,
                    systemImage: candidate.kind.activityIconName,
                    coordinate: candidate.coordinate
                )
                .tint(markerTint(for: candidate))
                .tag(candidate.id)
            }
            ForEach(Array(chosen.enumerated()), id: \.element.place.id) { number, item in
                Marker(item.place.name, monogram: Text("\(number + 1)"), coordinate: item.place.coordinate)
                    .tint(trip.theme.accentColor)
                    .tag(item.place.id)
            }
            if chosen.count > 1 {
                MapPolyline(coordinates: chosen.map(\.place.coordinate))
                    .stroke(trip.theme.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
            }
        }
        .mapFeatureSelectionDisabled { _ in true }
        .overlay(alignment: .topTrailing) {
            Button(action: resetMapView) {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Reset map view")
        }
        // Recreated per step so the camera re-fits that step's places.
        .id(model.currentStep)
    }

    private func markerTint(for candidate: Candidate) -> Color {
        if focusedID == candidate.id { return .orange }
        if model.selectedID == candidate.id { return trip.theme.accentColor }
        return .secondary
    }

    // MARK: Review

    private var reviewView: some View {
        let stops = model.plannedStops
        return VStack(spacing: 0) {
            Map(selection: $mapSelection) {
                ForEach(Array(stops.enumerated()), id: \.element.place.id) { number, item in
                    Marker(item.place.name, monogram: Text("\(number + 1)"), coordinate: item.place.coordinate)
                        .tint(trip.theme.accentColor)
                        .tag(item.place.id)
                }
                if stops.count > 1 {
                    MapPolyline(coordinates: stops.map(\.place.coordinate))
                        .stroke(trip.theme.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
                }
            }
            .containerRelativeFrame(.vertical) { height, _ in height * 0.34 }

            List {
                Section {
                    ForEach(Array(stops.enumerated()), id: \.element.place.id) { number, item in
                        Button {
                            model.goTo(item.index)
                        } label: {
                            reviewRow(number: number, step: item.step, place: item.place)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("Remove", systemImage: "trash", role: .destructive) {
                                withAnimation { model.removeStop(at: item.index) }
                            }
                        }
                    }

                    Button("Add another stop", systemImage: "plus.circle") {
                        model.addExtraStop()
                    }
                    .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                } header: {
                    Text("Your day")
                } footer: {
                    Text("Tap a stop to change its place or time. Always verify your selected locations (hours, location and availability) before you go.")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                model.commit(modelContext: modelContext, translations: translator.english)
                dismiss()
            } label: {
                Text(stops.count == 1 ? "Add 1 stop to day" : "Add \(stops.count) stops to day")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appPrimary)
            .disabled(stops.isEmpty)
            .padding()
            .background(.bar)
        }
    }

    private func reviewRow(number: Int, step: PlanStep, place: Candidate) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeLabel(hour: step.hour, minute: step.minute))
                .font(AppFont.barlowCondensed(18, weight: .semibold))
                .frame(width: 64, alignment: .leading)
                .foregroundStyle(trip.theme.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(number + 1). \(place.name)")
                    .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                if let translated = english(for: place.name) {
                    Label(translated, systemImage: "globe")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(trip.theme.accentColor)
                }
                Text("\(step.kind.title) · \(place.kind.displayName)")
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func timeLabel(hour: Int, minute: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: calendar.startOfDay(for: model.day)) ?? model.day
        return date.formatted(.dateTime.hour().minute())
    }

    // MARK: Defaults

    /// Pre-selects interests from the profile's preferred vacation types the
    /// first time the sheet appears — the traveler can still change them.
    /// Shopping is never pre-selected: it's a deliberate choice.
    private func seedInterestsFromProfile() {
        guard !hasSeededInterests else { return }
        hasSeededInterests = true
        guard let types = profiles.first?.preferredVacationTypes, !types.isEmpty else { return }
        var seeded = Set<Interest>()
        for type in types {
            switch type {
            case .beaches, .parks, .mountains, .province:
                seeded.insert(.nature)
            case .cities:
                seeded.insert(.culture)
            case .other:
                break
            }
        }
        if !seeded.isEmpty {
            model.interests = seeded
        }
    }
}
