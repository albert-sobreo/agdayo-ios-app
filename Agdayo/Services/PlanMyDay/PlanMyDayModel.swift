import CoreLocation
import Foundation
import Observation
import SwiftData

extension Trip {
    /// Every calendar day of the trip (local midnight), start through end.
    /// Capped so a mistyped end date can't produce thousands of rows.
    var calendarDays: [Date] {
        let calendar = Calendar.current
        var days: [Date] = []
        var day = calendar.startOfDay(for: startDate)
        let last = calendar.startOfDay(for: endDate)
        while day <= last, days.count < 120 {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }
}

/// One step of the guided day: a time, what it's for, and the place the
/// traveler picked (or skipped).
struct PlanStep: Identifiable, Equatable {
    let id = UUID()
    var kind: StepKind
    var hour: Int
    var minute: Int
    var chosen: Candidate?
    var isSkipped = false

    var minutesAfterMidnight: Int { hour * 60 + minute }
}

/// State + orchestration for the Plan My Day sheet. The traveler walks the
/// day one step at a time — breakfast, something to do, lunch… — picking a
/// place for each from nearby suggestions, then reviews the day and adds it
/// to the itinerary. No AI: the app finds places, the traveler decides.
@MainActor
@Observable
final class PlanMyDayModel {
    enum Phase: Equatable {
        case setup, loading, stepping, review, failed(String)
    }

    let trip: Trip
    var day: Date
    var interests: Set<Interest>
    var pace: Pace = .balanced
    /// How far from the day's base to look, in km (user-adjustable). A radius
    /// is a circle, not a city border, so results are grouped by city.
    var radiusKm: Double = 10

    private(set) var phase: Phase = .setup
    private(set) var steps: [PlanStep] = []
    private(set) var currentStep = 0

    // The current step's list controls.
    var sort: StepSort = .bestMatch
    var enabledKinds: Set<PlaceKind> = []
    var searchText = ""
    private(set) var searchResults: [Candidate] = []
    private(set) var isSearching = false
    /// The suggestion highlighted in the list, not yet confirmed.
    var selectedID: UUID?

    // Where this day is based. Resolved automatically per day (planned
    // activities, hotel, transport, trip) until the traveler picks a place.
    private(set) var base: PlanBase?
    private(set) var isBaseManual = false
    private(set) var isResolvingBase = false

    /// True while the current step's places are still being found.
    private(set) var isLoadingStep = false

    // The order the list was last shown in, per step and filter. Kept so a
    // redraw, or places arriving from background loading, can never reshuffle
    // rows under the traveler's finger: known rows keep their place, newcomers
    // go to the end of their group. Not observed: it's a cache, not UI state.
    @ObservationIgnored private var orderKey = ""
    @ObservationIgnored private var placeOrder: [UUID: Int] = [:]
    @ObservationIgnored private var groupOrder: [String: Int] = [:]

    private var candidates: [Candidate] = []
    private var loadedKinds: Set<PlaceKind> = []
    private var existingNames: Set<String> = []
    private var baseTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(trip: Trip, day: Date, interests: Set<Interest>) {
        self.trip = trip
        self.day = day
        self.interests = interests
    }

    private var radius: CLLocationDistance { radiusKm * 1_000 }

    /// A town uses the traveler's radius; a province or country reaches as
    /// far as that area does.
    private func searchRadius(for base: PlanBase) -> CLLocationDistance {
        guard base.isBroad else { return radius }
        return base.broadRadius > 0 ? base.broadRadius : 250_000
    }

    // MARK: Base location

    /// Re-derives the base for the current day unless the traveler chose one.
    func refreshBase() {
        guard !isBaseManual else { return }
        baseTask?.cancel()
        isResolvingBase = true
        let day = day
        baseTask = Task {
            let resolved = await DayBaseResolver.resolve(trip: trip, day: day)
            guard !Task.isCancelled else { return }
            base = resolved
            isResolvingBase = false
        }
    }

    func setBase(_ newBase: PlanBase) {
        baseTask?.cancel()
        isResolvingBase = false
        isBaseManual = true
        base = newBase
    }

    func resetBaseToAutomatic() {
        isBaseManual = false
        refreshBase()
    }

    // MARK: Flow

    /// Finds places around the base, then starts at the first step.
    func start() async {
        guard phase != .loading else { return }
        phase = .loading

        // Anything already in the itinerary is off the table, so a plan never
        // suggests a place that's on another day (or this one).
        existingNames = Set(trip.activities.map { Candidate.key($0.title) })

        if base == nil && !isBaseManual { base = await DayBaseResolver.resolve(trip: trip, day: day) }
        guard let base else {
            phase = .failed("Couldn't find \(trip.location) on the map. Pick a place to plan around and try again.")
            return
        }

        let templates = pace.steps
        steps = templates.map { PlanStep(kind: $0.kind, hour: $0.hour, minute: $0.minute) }
        candidates = []
        loadedKinds = []

        // Places are found one step at a time (each kind searches a whole
        // grid of the area), so only the first step has to be ready now.
        await ensureLoaded(for: 0)
        guard !Task.isCancelled else { return }
        guard !candidates.isEmpty else {
            phase = .failed("No places found around \(base.name). Try a wider area, another place, or check your connection.")
            return
        }

        goTo(0)
        phase = .stepping
    }

    func backToSetup() {
        searchTask?.cancel()
        phase = .setup
    }

    func goTo(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        currentStep = index
        let step = steps[index]
        enabledKinds = Set(step.kind.placeKinds(for: interests))
        sort = index == firstOpenIndex ? .bestMatch : .closest
        searchText = ""
        searchResults = []
        searchTask?.cancel()
        selectedID = step.chosen?.id
        phase = .stepping
        Task { await ensureLoaded(for: index) }
    }

    /// Finds places for a step's kinds the first time it's needed, then
    /// quietly prefetches the next step so it's ready when the traveler gets there.
    private func ensureLoaded(for index: Int) async {
        guard steps.indices.contains(index), let base else { return }
        let missing = steps[index].kind.placeKinds(for: interests).filter { !loadedKinds.contains($0) }
        if !missing.isEmpty {
            isLoadingStep = true
            let found = await PlaceSearchService.fetchCandidates(kinds: Set(missing), near: base.coordinate, radius: searchRadius(for: base), city: base.searchName, broad: base.isBroad)
            guard !Task.isCancelled else { isLoadingStep = false; return }
            loadedKinds.formUnion(missing)
            let known = Set(candidates.map { Candidate.key($0.name) })
            candidates += found.filter { !known.contains(Candidate.key($0.name)) }
            isLoadingStep = false
        }
        let next = index + 1
        if steps.indices.contains(next) {
            let upcoming = steps[next].kind.placeKinds(for: interests).filter { !loadedKinds.contains($0) }
            if !upcoming.isEmpty {
                let found = await PlaceSearchService.fetchCandidates(kinds: Set(upcoming), near: base.coordinate, radius: searchRadius(for: base), city: base.searchName, broad: base.isBroad)
                guard !Task.isCancelled else { return }
                loadedKinds.formUnion(upcoming)
                let known = Set(candidates.map { Candidate.key($0.name) })
                candidates += found.filter { !known.contains(Candidate.key($0.name)) }
            }
        }
    }

    private var firstOpenIndex: Int {
        steps.firstIndex { $0.chosen == nil && !$0.isSkipped } ?? 0
    }

    /// Confirms the highlighted place for this step and moves on.
    func confirmSelection() {
        guard steps.indices.contains(currentStep), let candidate = selectedCandidate else { return }
        steps[currentStep].chosen = candidate
        steps[currentStep].isSkipped = false
        advance()
    }

    func skipStep() {
        guard steps.indices.contains(currentStep) else { return }
        steps[currentStep].chosen = nil
        steps[currentStep].isSkipped = true
        advance()
    }

    func previousStep() {
        if currentStep > 0 { goTo(currentStep - 1) } else { backToSetup() }
    }

    private func advance() {
        let next = currentStep + 1
        guard steps.indices.contains(next) else {
            phase = .review
            return
        }
        suggestTime(for: next)
        goTo(next)
    }

    /// Adds one more "something to do" step after the last, from review.
    func addExtraStop() {
        let last = steps.last
        let minutes = min((last?.minutesAfterMidnight ?? 17 * 60) + 90, 22 * 60)
        steps.append(PlanStep(kind: .activity, hour: minutes / 60, minute: minutes % 60 / 15 * 15))
        suggestTime(for: steps.count - 1)
        goTo(steps.count - 1)
    }

    func removeStop(at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps[index].chosen = nil
        steps[index].isSkipped = true
    }

    // MARK: Times

    func timeDate(for index: Int) -> Date {
        guard steps.indices.contains(index) else { return day }
        let calendar = Calendar.current
        return calendar.date(
            bySettingHour: steps[index].hour, minute: steps[index].minute, second: 0,
            of: calendar.startOfDay(for: day)
        ) ?? day
    }

    func setTime(_ date: Date, for index: Int) {
        guard steps.indices.contains(index) else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        steps[index].hour = parts.hour ?? steps[index].hour
        steps[index].minute = parts.minute ?? steps[index].minute
    }

    /// Nudges the next step's default time later when the previous stop
    /// (plus time there and travel) would run past it. The traveler can
    /// still change it.
    private func suggestTime(for index: Int) {
        guard steps.indices.contains(index),
              let previous = steps[..<index].last(where: { $0.chosen != nil }),
              let place = previous.chosen else { return }
        // Time at the previous stop plus a short hop to the next one.
        let finish = previous.minutesAfterMidnight + Self.dwellMinutes(for: place.kind) + 15
        let rounded = (finish + 14) / 15 * 15
        if rounded > steps[index].minutesAfterMidnight, rounded < 23 * 60 {
            steps[index].hour = rounded / 60
            steps[index].minute = rounded % 60
        }
    }

    nonisolated static func dwellMinutes(for kind: PlaceKind) -> Int {
        switch kind {
        case .zoo, .aquarium, .amusementPark: return 150
        case .beach, .nationalPark, .theater: return 120
        case .museum: return 90
        case .park, .store, .restaurant, .nightlife: return 75
        default: return 45
        }
    }

    /// Interleaves places across ~1.5 km cells (best of each cell first), so
    /// the top of a list spreads across the area instead of piling up around
    /// the center.
    nonisolated static func spread(_ places: [Candidate]) -> [Candidate] {
        // Places Apple ranked keep that order; only the unranked rest is
        // spread out, otherwise the ranking would be scrambled.
        let ranked = places.filter { $0.prominence > 0 }
        let unranked = places.filter { $0.prominence <= 0 }
        return ranked + spreadAcrossCells(unranked)
    }

    nonisolated private static func spreadAcrossCells(_ places: [Candidate]) -> [Candidate] {
        var buckets: [[Int]: [Candidate]] = [:]
        var order: [[Int]] = []
        for place in places {
            let key = [Int((place.latitude / 0.015).rounded(.down)), Int((place.longitude / 0.015).rounded(.down))]
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(place)
        }
        var result: [Candidate] = []
        var round = 0
        while result.count < places.count {
            for key in order {
                if let list = buckets[key], round < list.count { result.append(list[round]) }
            }
            round += 1
        }
        return result
    }

    /// Door-to-door city travel estimate: detours included, about 20 km/h.
    nonisolated static func travelMinutes(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Int {
        let km = Candidate.distance(from: from, to: to) / 1_000 * 1.4
        return max(10, Int((km / 20 * 60).rounded()))
    }

    // MARK: Suggestions

    /// The base's city/town name, used for the "only in …" filter.
    var cityName: String? {
        let name = base?.searchName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? nil : name
    }

    var currentKind: StepKind? {
        steps.indices.contains(currentStep) ? steps[currentStep].kind : nil
    }

    /// Kinds the current step can show, for the filter chips.
    var availableKinds: [PlaceKind] {
        guard let kind = currentKind else { return [] }
        return kind.placeKinds(for: interests)
    }

    /// Where distances are measured from: the last confirmed stop before
    /// this step, else the day's base.
    var referencePoint: CLLocationCoordinate2D? {
        let previous = steps[..<min(currentStep, steps.count)].last { $0.chosen != nil }?.chosen
        return previous?.coordinate ?? base?.coordinate
    }

    var referenceName: String {
        let hasPrevious = steps[..<min(currentStep, steps.count)].contains { $0.chosen != nil }
        return hasPrevious ? "previous stop" : "your starting point"
    }

    /// Places for the current step: the search results when the traveler is
    /// searching, otherwise the nearby suggestions filtered and sorted.
    private var sortedSuggestions: [Candidate] {
        guard currentKind != nil else { return [] }
        let chosenNames = Set(steps.compactMap { $0.chosen }.map { Candidate.key($0.name) })
        let taken = existingNames.union(chosenNames)
        let ownChoice = steps.indices.contains(currentStep) ? steps[currentStep].chosen : nil

        let pool: [Candidate]
        if !searchResults.isEmpty {
            pool = searchResults
        } else {
            pool = candidates.filter { enabledKinds.contains($0.kind) }
        }

        let origin = referencePoint
        let usable = pool.filter { candidate in
            let key = Candidate.key(candidate.name)
            // A step's own pick stays visible so it can be re-selected.
            return !taken.contains(key) || candidate.id == ownChoice?.id
        }

        func distance(_ candidate: Candidate) -> Double {
            origin.map { Candidate.distance(from: $0, to: candidate.coordinate) } ?? 0
        }

        let sorted: [Candidate]
        switch sort {
        case .bestMatch:
            sorted = usable.sorted {
                $0.prominence != $1.prominence ? $0.prominence > $1.prominence : distance($0) < distance($1)
            }
        case .closest:
            sorted = usable.sorted { distance($0) < distance($1) }
        }
        return sorted
    }

    /// A city's worth of suggestions in the list.
    struct CityGroup: Identifiable {
        let id: String
        let name: String
        /// The destination's own city (shows the "Your destination" pill).
        let isMain: Bool
        /// Shown open by default: the destination, or when the destination is a
        /// large area with no city of its own (Tokyo), its busiest district.
        let isLead: Bool
        let places: [Candidate]
    }

    /// The step's places grouped by city: the destination's city first, then
    /// other cities nearest-first (busiest first for a large area), then
    /// anything MapKit gave no city for. Spellings of one place ("Shinjuku",
    /// "Shinjuku-Ku", "新宿区") are merged into a single group.
    var cityGroups: [CityGroup] {
        let sorted = sortedSuggestions
        guard searchResults.isEmpty else {
            return [CityGroup(id: "search", name: "Search results", isMain: false, isLead: true, places: Array(sorted.prefix(40)))]
        }

        let main = cityName.map { Candidate.cityKey($0) }
        let origin = referencePoint
        let isBroad = base?.isBroad == true
        func isMain(_ key: String) -> Bool {
            guard let main, !key.isEmpty else { return false }
            return key == main || key.contains(main) || main.contains(key)
        }

        let grouped = Dictionary(grouping: sorted) { Candidate.cityKey($0.city) }
        var groups = grouped.map { key, places -> (key: String, nearest: Double, weight: Double, group: CityGroup) in
            let name = places.first?.city ?? "Other areas"
            let nearest = places.map { place in
                origin.map { Candidate.distance(from: $0, to: place.coordinate) } ?? 0
            }.min() ?? 0
            // How much Apple ranked this district's places, for large areas.
            let weight = places.map { max($0.prominence, 0) }.reduce(0, +)
            let main = isMain(key)
            return (key, nearest, weight, CityGroup(
                id: key.isEmpty ? "other" : key,
                name: name,
                isMain: main,
                isLead: main,
                places: Array((sort == .bestMatch ? Self.spread(places) : places).prefix(main ? 40 : 25))
            ))
        }
        groups.sort { lhs, rhs in
            if lhs.group.isMain != rhs.group.isMain { return lhs.group.isMain }
            if lhs.key.isEmpty != rhs.key.isEmpty { return !lhs.key.isEmpty }
            return isBroad ? lhs.weight > rhs.weight : lhs.nearest < rhs.nearest
        }

        // No group matches the destination (it's a large area): open the first.
        var result = groups.map(\.group)
        if !result.contains(where: \.isMain), let first = result.first, !first.id.isEmpty {
            result[0] = CityGroup(id: first.id, name: first.name, isMain: false, isLead: true, places: first.places)
        }
        return stabilized(result)
    }

    /// Keeps groups and rows where they were last shown (see `placeOrder`).
    /// A new step, sort, filter or search starts a fresh order.
    private func stabilized(_ groups: [CityGroup]) -> [CityGroup] {
        let key = "\(currentStep)|\(sort.rawValue)|\(enabledKinds.map(\.rawValue).sorted().joined(separator: ","))|\(searchResults.count)"
        if key != orderKey {
            orderKey = key
            placeOrder = [:]
            groupOrder = [:]
        }

        let knownGroups = groups.filter { groupOrder[$0.id] != nil }.sorted { groupOrder[$0.id]! < groupOrder[$1.id]! }
        let newGroups = groups.filter { groupOrder[$0.id] == nil }
        let ordered = (knownGroups + newGroups).map { group -> CityGroup in
            let known = group.places.filter { placeOrder[$0.id] != nil }.sorted { placeOrder[$0.id]! < placeOrder[$1.id]! }
            let fresh = group.places.filter { placeOrder[$0.id] == nil }
            return CityGroup(id: group.id, name: group.name, isMain: group.isMain, isLead: group.isLead, places: known + fresh)
        }

        groupOrder = [:]
        placeOrder = [:]
        var position = 0
        for (index, group) in ordered.enumerated() {
            groupOrder[group.id] = index
            for place in group.places where placeOrder[place.id] == nil {
                placeOrder[place.id] = position
                position += 1
            }
        }
        return ordered
    }

    /// Everything shown for the step, in list order (city by city).
    var suggestions: [Candidate] {
        cityGroups.flatMap(\.places)
    }

    var selectedCandidate: Candidate? {
        guard let selectedID else { return nil }
        return suggestions.first { $0.id == selectedID }
            ?? steps[safe: currentStep]?.chosen.flatMap { $0.id == selectedID ? $0 : nil }
    }

    func distanceFromReference(_ candidate: Candidate) -> CLLocationDistance? {
        referencePoint.map { Candidate.distance(from: $0, to: candidate.coordinate) }
    }

    func toggleKind(_ kind: PlaceKind) {
        if enabledKinds.contains(kind) {
            if enabledKinds.count > 1 { enabledKinds.remove(kind) }
        } else {
            enabledKinds.insert(kind)
        }
    }

    /// Runs a free-text search near the base (called when the traveler submits the search field).
    func runSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let base else {
            searchResults = []
            return
        }
        isSearching = true
        let radius = radius
        searchTask = Task {
            let found = await PlaceSearchService.search(query: query, near: base.coordinate, radius: radius)
            guard !Task.isCancelled else { return }
            searchResults = found
            isSearching = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        searchResults = []
        isSearching = false
    }

    // MARK: Review & saving

    /// Confirmed stops in time order.
    var plannedStops: [(index: Int, step: PlanStep, place: Candidate)] {
        steps.enumerated()
            .compactMap { index, step in step.chosen.map { (index, step, $0) } }
            .sorted { $0.step.minutesAfterMidnight < $1.step.minutesAfterMidnight }
    }

    /// Turns every confirmed stop into a regular activity at its time on the
    /// chosen day (local calendar, same as the rest of the app).
    func commit(modelContext: ModelContext, translations: [String: String] = [:]) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        for (_, step, place) in plannedStops {
            let date = calendar.date(bySettingHour: step.hour, minute: step.minute, second: 0, of: dayStart) ?? dayStart
            let location = place.locality.map { "\(place.name), \($0)" } ?? place.name
            let english = translations[place.name].map { "English: \($0)" } ?? ""
            ActivitySaver.insert(
                title: place.name,
                description: english,
                location: location,
                coordinate: place.coordinate,
                date: date,
                iconName: place.kind.activityIconName,
                trip: trip,
                modelContext: modelContext
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
