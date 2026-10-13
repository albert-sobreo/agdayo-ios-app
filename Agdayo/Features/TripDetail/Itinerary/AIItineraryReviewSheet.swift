import SwiftUI
import SwiftData
import MapKit

/// A chat-shaped "ask AI" flow — NOT a real conversation. Every submitted
/// prompt is an independent, one-shot generation (no model memory between
/// turns); the transcript look is purely a UI convenience for issuing
/// several asks in a row (e.g. lunch, then dinner, then activities) and
/// accumulating selections across all of them before one final commit.
/// Each response renders as one or more labeled groups of 2-5 selectable
/// options — a single flat group for a one-off category ask ("lunch
/// suggestions"), several day-grouped ones for a multi-day plan ask — never
/// auto-applied; the user checks what they want, then taps "Add N to
/// Itinerary" once at the end.
@available(iOS 26.0, *)
struct AIItineraryReviewSheet: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private struct Turn: Identifiable {
        let id = UUID()
        let prompt: String
        var groups: [SuggestionGroup] = []
        var isGenerating = true
        var errorMessage: String?
    }

    private struct DayHeaderEntry: Identifiable {
        let id = UUID()
        let date: String
        var indices: [Int]
    }

    @State private var turns: [Turn] = []
    @State private var composerText: String = ""
    /// Fetched once per sheet session — a pure function of the trip's
    /// location, so there's no reason to re-fetch it for every turn.
    @State private var discoveredPlaces: [TripPlaceDiscovery.PlaceCandidate]?
    /// Carries the previous turn's top pick forward so distance ranking
    /// stays continuous across turns instead of re-anchoring on the trip's
    /// general location every time.
    @State private var sessionAnchor: CLLocationCoordinate2D?
    /// uid = "\(turn.id)-\(groupIndex)"; value is the set of selected
    /// option indices within that group.
    @State private var selectedOptionIndices: [String: Set<Int>] = [:]
    /// uid = "\(groupID)-\(optionIndex)"
    @State private var etaCaptions: [String: String] = [:]
    /// Keyed by `option.location` — intentionally shared across every turn
    /// in the session: the same place name always resolves to the same
    /// coordinate, so there's no reason to re-resolve it per turn.
    @State private var resolvedCoordinates: [String: CLLocationCoordinate2D] = [:]

    /// Minimum gap between two activities landing on the same instant, so
    /// committing more than one doesn't schedule them at the same time —
    /// both within one group's selections and across unrelated turns that
    /// happened to pick the same placeholder slot.
    private static let staggerInterval: TimeInterval = 90 * 60

    private var selectedCount: Int {
        selectedOptionIndices.values.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        NavigationStack {
            transcript
                .safeAreaInset(edge: .bottom) {
                    composerBar
                }
                .navigationTitle("Ask AI")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if selectedCount > 0 {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Add \(selectedCount) to Itinerary") {
                                commit()
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if turns.isEmpty {
            emptyTranscript
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(turns) { turn in
                            turnView(turn)
                                .id(turn.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: turns.count) { _, _ in
                    scrollToLast(proxy)
                }
                .onChange(of: turns.last?.isGenerating) { _, _ in
                    scrollToLast(proxy)
                }
            }
        }
    }

    private var emptyTranscript: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(trip.theme.accentColor)
            Text("Ask for lunch spots, a day plan, or anything else for \(trip.location).")
                .font(AppFont.outfit(14, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scrollToLast(_ proxy: ScrollViewProxy) {
        guard let last = turns.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func turnView(_ turn: Turn) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            Text(turn.prompt)
                .font(AppFont.outfit(14, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(trip.theme.accentColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)

            if turn.isGenerating {
                HStack {
                    ShimmerText(
                        text: "Thinking…",
                        font: AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline)
                    )
                    Spacer()
                }
            } else if let errorMessage = turn.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(AppFont.outfit(13, relativeTo: .footnote))
                        .foregroundStyle(.red)
                    Button {
                        Task { await retry(turn) }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .font(AppFont.outfit(13, weight: .semibold, relativeTo: .footnote))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                groupsView(for: turn)
            }
        }
    }

    @ViewBuilder
    private func groupsView(for turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if turn.groups.count > 1 {
                ForEach(dayHeaders(for: turn.groups)) { entry in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayHeaderText(entry.date))
                            .font(AppFont.outfit(13, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                        ForEach(entry.indices, id: \.self) { groupIndex in
                            groupSection(turn.groups[groupIndex], turn: turn, groupIndex: groupIndex)
                        }
                    }
                }
            } else if let only = turn.groups.first {
                groupSection(only, turn: turn, groupIndex: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Runs consecutive groups sharing the same `date` together under one
    /// day header — preserves today's day-plan look for a multi-group
    /// response without needing the model to self-report "this is a plan."
    private func dayHeaders(for groups: [SuggestionGroup]) -> [DayHeaderEntry] {
        var result: [DayHeaderEntry] = []
        for (index, group) in groups.enumerated() {
            if let last = result.last, last.date == group.date {
                result[result.count - 1].indices.append(index)
            } else {
                result.append(DayHeaderEntry(date: group.date, indices: [index]))
            }
        }
        return result
    }

    private func dayHeaderText(_ dateString: String) -> String {
        guard let date = Self.isoDateFormatter.date(from: dateString) else { return dateString }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    private func groupSection(_ group: SuggestionGroup, turn: Turn, groupIndex: Int) -> some View {
        let groupID = "\(turn.id)-\(groupIndex)"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(group.label.uppercased())
                Text("· \(group.time)")
            }
            .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
            .foregroundStyle(.secondary)

            ForEach(Array(group.options.enumerated()), id: \.offset) { optionIndex, option in
                optionRow(option, optionIndex: optionIndex, groupID: groupID)
            }
        }
        .padding(.vertical, 4)
    }

    private func optionRow(_ option: SuggestionOption, optionIndex: Int, groupID: String) -> some View {
        let isSelected = selectedOptionIndices[groupID]?.contains(optionIndex) ?? false
        let isRecommended = optionIndex == 0
        let etaKey = "\(groupID)-\(optionIndex)"
        return Button {
            toggleSelection(optionIndex: optionIndex, groupID: groupID)
            if isSelected == false {
                Task { await loadETA(for: option, key: etaKey) }
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.appPrimary : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: clampedIconName(option.iconName))
                            .foregroundStyle(trip.theme.accentColor)
                        Text(option.title)
                            .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                        if isRecommended {
                            PillTag(text: "Recommended", background: trip.theme.lightTintColor, foreground: trip.theme.accentColor)
                        }
                    }
                    if !option.location.isEmpty {
                        Text(option.location)
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text(option.cost.formattedCurrency(code: validCurrencyCode(option.costCurrency)))
                        if isSelected, let eta = etaCaptions[etaKey] {
                            Text("· \(eta)")
                        }
                    }
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var composerBar: some View {
        let isSending = turns.last?.isGenerating ?? false
        let canSend = !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask for lunch spots, a day plan…", text: $composerText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? trip.theme.accentColor : Color.secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func toggleSelection(optionIndex: Int, groupID: String) {
        var current = selectedOptionIndices[groupID] ?? []
        if current.contains(optionIndex) {
            current.remove(optionIndex)
        } else {
            current.insert(optionIndex)
        }
        selectedOptionIndices[groupID] = current
    }

    private func clampedIconName(_ iconName: String) -> String {
        ActivityIconLibrary.allIcons.contains(iconName) ? iconName : "mappin.and.ellipse"
    }

    private func send() {
        let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        composerText = ""
        let turn = Turn(prompt: trimmed)
        turns.append(turn)
        Task { await generate(turnID: turn.id, prompt: trimmed) }
    }

    private func retry(_ turn: Turn) async {
        updateTurn(turn.id) {
            $0.isGenerating = true
            $0.errorMessage = nil
        }
        await generate(turnID: turn.id, prompt: turn.prompt)
    }

    private func updateTurn(_ id: UUID, _ mutate: (inout Turn) -> Void) {
        guard let index = turns.firstIndex(where: { $0.id == id }) else { return }
        mutate(&turns[index])
    }

    private func generate(turnID: UUID, prompt: String) async {
        do {
            let places = await places(for: trip)
            let groups = try await AISuggestionService.generate(
                for: trip,
                prompt: prompt,
                places: places,
                priorSuggestionsSummary: priorSuggestionsSummary(),
                anchor: sessionAnchor ?? trip.coordinate
            )
            updateTurn(turnID) {
                $0.groups = groups
                $0.isGenerating = false
            }
            initializeSelections(for: groups, turnID: turnID)
            await loadInitialETAs(for: groups, turnID: turnID)
        } catch {
            updateTurn(turnID) {
                $0.isGenerating = false
                $0.errorMessage = error.localizedDescription
            }
        }
    }

    private func places(for trip: Trip) async -> [TripPlaceDiscovery.PlaceCandidate] {
        if let discoveredPlaces {
            return discoveredPlaces
        }
        let center = trip.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let places = await TripPlaceDiscovery.search(near: center, destination: trip.location)
        discoveredPlaces = places
        return places
    }

    /// Every option generated so far this session (selected or not),
    /// handed back to `AISuggestionService` so a later ask doesn't repeat
    /// an earlier suggestion or its time slot.
    private func priorSuggestionsSummary() -> String {
        let entries = turns.flatMap { turn in
            turn.groups.flatMap { group in
                group.options.map { option in "- \(group.date) \(group.time): \(option.title) — \(option.location)" }
            }
        }
        return entries.isEmpty ? "Nothing suggested yet." : entries.joined(separator: "\n")
    }

    /// Every block defaults to just its recommended (closest-ranked) option
    /// checked — committing with zero taps still produces a geographically
    /// coherent result. Users can check additional options per group.
    private func initializeSelections(for groups: [SuggestionGroup], turnID: UUID) {
        for (groupIndex, group) in groups.enumerated() where !group.options.isEmpty {
            selectedOptionIndices["\(turnID)-\(groupIndex)"] = [0]
        }
    }

    private func loadInitialETAs(for groups: [SuggestionGroup], turnID: UUID) async {
        var anchor = sessionAnchor ?? trip.coordinate
        for (groupIndex, group) in groups.enumerated() {
            guard let first = group.options.first else { continue }
            let groupID = "\(turnID)-\(groupIndex)"
            if let anchor {
                await loadETA(for: first, key: "\(groupID)-0", anchor: anchor)
            }
            anchor = await ItineraryDistanceRanking.resolveCoordinate(
                for: first.location,
                near: trip.coordinate ?? anchor ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            )
        }
        // Carry this turn's top pick forward as the anchor for the next ask.
        sessionAnchor = anchor ?? sessionAnchor
    }

    private func loadETA(for option: SuggestionOption, key: String, anchor: CLLocationCoordinate2D? = nil) async {
        guard let tripCenter = trip.coordinate else { return }
        let from = anchor ?? tripCenter
        guard let to = await ItineraryDistanceRanking.resolveCoordinate(for: option.location, near: tripCenter) else { return }
        resolvedCoordinates[option.location] = to
        guard let estimate = try? await TravelEstimateService.estimate(from: from, to: to, transportType: .automobile) else { return }
        etaCaptions[key] = formattedETA(estimate)
    }

    /// The model is asked for a 3-letter code but isn't guaranteed to comply —
    /// fall back to the trip's own currency if what it returned looks invalid.
    private func validCurrencyCode(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.count == 3 ? trimmed : trip.currency
    }

    private func formattedETA(_ estimate: TravelEstimate) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        formatter.maximumUnitCount = 2
        let time = formatter.string(from: estimate.duration) ?? "\(Int(estimate.duration / 60)) min"
        return "\(time) away"
    }

    /// Commits every selected option across every turn in one pass. A
    /// running `claimedDates` set guards against two independent turns
    /// (which share no context with each other) landing on the exact same
    /// placeholder date/time — nudging forward by `staggerInterval` until
    /// the slot is free, on top of the existing within-group staggering.
    private func commit() {
        var claimedDates: Set<Date> = []
        for turn in turns {
            for (groupIndex, group) in turn.groups.enumerated() {
                let groupID = "\(turn.id)-\(groupIndex)"
                let indices = (selectedOptionIndices[groupID] ?? []).sorted()
                guard !indices.isEmpty else { continue }
                let baseDate = Self.combine(dateString: group.date, timeString: group.time) ?? trip.startDate
                for (position, optionIndex) in indices.enumerated() {
                    guard optionIndex < group.options.count else { continue }
                    var scheduledDate = baseDate.addingTimeInterval(TimeInterval(position) * Self.staggerInterval)
                    while claimedDates.contains(scheduledDate) {
                        scheduledDate = scheduledDate.addingTimeInterval(Self.staggerInterval)
                    }
                    claimedDates.insert(scheduledDate)
                    insertActivity(from: group.options[optionIndex], date: scheduledDate)
                }
            }
        }
        dismiss()
    }

    private func insertActivity(from option: SuggestionOption, date: Date) {
        let coordinate = resolvedCoordinates[option.location]
        let currencyCode = validCurrencyCode(option.costCurrency)
        let activity = Activity(
            title: option.title,
            activityDescription: option.description,
            location: option.location,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            date: date,
            cost: option.cost > 0 ? option.cost : nil,
            costCurrency: option.cost > 0 ? currencyCode : nil,
            iconName: clampedIconName(option.iconName),
            trip: trip
        )
        modelContext.insert(activity)
        pushIfShared(activity)
        if option.cost > 0, currencyCode != trip.currency {
            applyExchangeRate(for: activity, from: currencyCode)
        }
    }

    /// Snapshots a conversion rate onto the activity so it still counts
    /// toward budget totals/balances (see `Activity.costAndRate`), which
    /// otherwise excludes any cost whose currency doesn't match the trip's
    /// and has no rate recorded.
    private func applyExchangeRate(for activity: Activity, from currencyCode: String) {
        let tripCurrency = trip.currency
        Task {
            guard let rate = await CurrencyConversionService.fetchRate(from: currencyCode, to: tripCurrency) else { return }
            activity.exchangeRateToTripCurrency = rate
            pushIfShared(activity)
        }
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

    /// Deliberately local time zone (the `DateFormatter` default), not
    /// UTC — `AISuggestionService` sends/reads these dates in the device's
    /// local calendar day too (see its `isoDateString(from:)`), matching
    /// how `trip.startDate`/`endDate` are anchored. Parsing as UTC here
    /// shifted every committed activity back a day for anyone east of UTC.
    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func combine(dateString: String, timeString: String) -> Date? {
        guard let day = isoDateFormatter.date(from: dateString) else { return nil }
        let parts = timeString.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return day }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: day) ?? day
    }
}
