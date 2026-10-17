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

/// State + orchestration for the Plan My Day sheet: gathers MapKit
/// candidates, hands them to `DayPlanner`, and turns the accepted stops into
/// real activities. Candidates and the anchor are kept so Shuffle re-plans
/// instantly without another search.
@MainActor
@Observable
final class PlanMyDayModel {
    enum Phase: Equatable {
        case setup, loading, results, failed(String)
    }

    let trip: Trip
    var day: Date
    var interests: Set<Interest>
    var pace: Pace = .balanced

    private(set) var phase: Phase = .setup
    private(set) var stops: [PlannedStop] = []

    private var candidates: [Candidate] = []
    private var anchor: CLLocationCoordinate2D?
    private var excludedNames: Set<String> = []

    init(trip: Trip, day: Date, interests: Set<Interest>) {
        self.trip = trip
        self.day = day
        self.interests = interests
    }

    var plannedCount: Int {
        stops.filter { $0.candidate != nil }.count
    }

    func plan() async {
        guard phase != .loading else { return }
        phase = .loading

        // Anything already in the itinerary is off the table, so a plan never
        // suggests a place that's on another day (or this one).
        excludedNames = Set(trip.activities.map(\.title))

        guard let center = await PlaceSearchService.searchCenter(for: trip) else {
            phase = .failed("Couldn't find \(trip.location) on the map. Check the trip's destination and try again.")
            return
        }

        let kinds = DayPlanner.requiredKinds(pace: pace, interests: interests)
        candidates = await PlaceSearchService.fetchCandidates(kinds: kinds, near: center)
        guard !candidates.isEmpty else {
            phase = .failed("No places found nearby. Try different interests, or check your connection.")
            return
        }

        let hotel = await PlaceSearchService.hotelAnchor(for: trip, day: day, near: center)
        anchor = DayPlanner.chooseAnchor(candidates: candidates, preferred: hotel)
        replan(topChoices: 1)
        phase = .results
    }

    /// Re-runs the planner on the cached candidates, picking randomly among
    /// the 3 nearest for each slot — different places, same compact route.
    func shuffle() {
        replan(topChoices: 3)
    }

    func remove(_ stop: PlannedStop) {
        stops.removeAll { $0.id == stop.id }
    }

    func backToSetup() {
        phase = .setup
    }

    /// Turns every filled stop into a regular activity at its slot time on
    /// the chosen day (local calendar, same as the rest of the app).
    func commit(modelContext: ModelContext) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        for stop in stops {
            guard let candidate = stop.candidate else { continue }
            let date = calendar.date(bySettingHour: stop.slot.hour, minute: stop.slot.minute, second: 0, of: dayStart) ?? dayStart
            let location = candidate.locality.map { "\(candidate.name), \($0)" } ?? candidate.name
            ActivitySaver.insert(
                title: candidate.name,
                location: location,
                coordinate: candidate.coordinate,
                date: date,
                iconName: candidate.kind.activityIconName,
                trip: trip,
                modelContext: modelContext
            )
        }
    }

    private func replan(topChoices: Int) {
        guard let anchor else { return }
        stops = DayPlanner.plan(
            candidates: candidates,
            pace: pace,
            interests: interests,
            anchor: anchor,
            excludedNames: excludedNames,
            topChoices: topChoices
        )
    }
}
