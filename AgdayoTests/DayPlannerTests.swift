import CoreLocation
import Foundation
import Testing
@testable import Agdayo

/// SplitMix64 — a seedable generator so shuffle tests are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// A point `meters` due north of a fixed origin (~111,320 m per degree of
/// latitude), so distances in tests are easy to reason about.
private func point(_ meters: Double) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: 14.0 + meters / 111_320, longitude: 121.0)
}

private let origin = point(0)

private func candidate(_ name: String, _ kind: PlaceKind, at meters: Double) -> Candidate {
    Candidate(name: name, kind: kind, coordinate: point(meters))
}

struct DayPlannerTests {
    @Test func sightKindsAreTheUnionOfSelectedInterests() {
        let kinds = Set(DayPlanner.kinds(for: .sight, interests: [.culture, .family]))
        #expect(kinds == [.museum, .theater, .zoo, .aquarium, .amusementPark])
    }

    @Test func sightKindsFallBackWhenNothingContributes() {
        #expect(Set(DayPlanner.kinds(for: .sight, interests: [])) == [.museum, .park])
        // Nightlife only feeds the evening slot, so it contributes no sights.
        #expect(Set(DayPlanner.kinds(for: .sight, interests: [.nightlife])) == [.museum, .park])
    }

    @Test func eveningIncludesNightlifeOnlyWhenSelected() {
        #expect(Set(DayPlanner.kinds(for: .evening, interests: [.food])) == [.restaurant])
        #expect(Set(DayPlanner.kinds(for: .evening, interests: [.nightlife])) == [.restaurant, .nightlife])
    }

    @Test func requiredKindsCoverEverySlotInThePace() {
        let kinds = DayPlanner.requiredKinds(pace: .packed, interests: [.culture])
        #expect(kinds == [.museum, .theater, .restaurant, .cafe, .bakery])
    }

    @Test func fillsEachSlotWithTheNearestMatchFromThePreviousStop() {
        let candidates = [
            candidate("Far Museum", .museum, at: 1_500),
            candidate("Near Museum", .museum, at: 300),
            candidate("Lunch Near Museum", .restaurant, at: 500),
            candidate("Lunch By Anchor", .restaurant, at: 50),
            candidate("Dinner Spot", .restaurant, at: 900),
        ]
        let stops = DayPlanner.plan(candidates: candidates, pace: .relaxed, interests: [.culture], anchor: origin)

        // Each pick is measured from the previous stop, not the anchor: from
        // the museum (300 m) lunch is 200 m away vs 250 m; from that lunch
        // (500 m) dinner is 400 m away vs 450 m.
        #expect(stops.map { $0.candidate?.name } == ["Near Museum", "Lunch Near Museum", "Dinner Spot"])
    }

    @Test func neverRepeatsAPlaceAcrossSlots() {
        let candidates = [
            candidate("Only Restaurant", .restaurant, at: 200),
            candidate("A Museum", .museum, at: 100),
        ]
        let stops = DayPlanner.plan(candidates: candidates, pace: .relaxed, interests: [.culture], anchor: origin)
        let names = stops.compactMap { $0.candidate?.name }
        #expect(names.count == Set(names).count)
        #expect(stops[1].candidate?.name == "Only Restaurant")
        #expect(stops[2].candidate == nil)
    }

    @Test func slotStaysEmptyWhenNothingMatches() {
        let stops = DayPlanner.plan(candidates: [], pace: .relaxed, interests: [.culture], anchor: origin)
        #expect(stops.allSatisfy { $0.candidate == nil })
    }

    @Test func widensTheRadiusBeforeGivingUp() {
        let threeKm = [candidate("Distant Restaurant", .restaurant, at: 3_000)]
        let widened = DayPlanner.plan(candidates: threeKm, pace: .relaxed, interests: [], anchor: origin)
        #expect(widened[1].candidate?.name == "Distant Restaurant")

        let fiveKm = [candidate("Too Far Restaurant", .restaurant, at: 5_000)]
        let none = DayPlanner.plan(candidates: fiveKm, pace: .relaxed, interests: [], anchor: origin)
        #expect(none[1].candidate == nil)
    }

    @Test func skipsPlacesAlreadyUsedElsewhere() {
        let candidates = [
            candidate("Already Planned Cafe", .restaurant, at: 100),
            candidate("Fresh Restaurant", .restaurant, at: 400),
        ]
        let stops = DayPlanner.plan(
            candidates: candidates, pace: .relaxed, interests: [],
            anchor: origin, excludedNames: ["  already planned CAFE "]
        )
        #expect(stops[1].candidate?.name == "Fresh Restaurant")
    }

    @Test func anchorPrefersTheHotelWhenThereIsOne() {
        let hotel = point(5_000)
        let anchor = DayPlanner.chooseAnchor(candidates: [candidate("A", .museum, at: 0)], preferred: hotel)
        #expect(anchor?.latitude == hotel.latitude)
    }

    @Test func anchorFallsBackToTheDensestCluster() {
        let candidates = [
            candidate("Isolated", .museum, at: 10_000),
            candidate("Cluster 1", .museum, at: 0),
            candidate("Cluster 2", .park, at: 200),
            candidate("Cluster 3", .restaurant, at: 400),
        ]
        let anchor = DayPlanner.chooseAnchor(candidates: candidates, preferred: nil)
        let isolated = point(10_000)
        #expect(anchor != nil)
        #expect(DayPlanner.distance(from: anchor!, to: isolated) > 5_000)
        #expect(DayPlanner.chooseAnchor(candidates: [], preferred: nil) == nil)
    }

    @Test func shuffleOnlyEverPicksFromTheNearestFew() {
        let candidates = (1...6).map { candidate("Museum \($0)", .museum, at: Double($0) * 100) }
        let nearestThree: Set<String> = ["Museum 1", "Museum 2", "Museum 3"]
        var seen = Set<String>()

        for seed in 1...40 {
            var generator = SeededGenerator(state: UInt64(seed))
            let stops = DayPlanner.plan(
                candidates: candidates, pace: .relaxed, interests: [.culture],
                anchor: origin, topChoices: 3, using: &generator
            )
            let first = stops[0].candidate!.name
            #expect(nearestThree.contains(first))
            seen.insert(first)
        }
        // Across many seeds it should actually vary, not always pick #1.
        #expect(seen.count > 1)
    }

    @Test func defaultPlanningIsDeterministicallyTheNearest() {
        let candidates = (1...6).map { candidate("Museum \($0)", .museum, at: Double($0) * 100) }
        for _ in 0..<10 {
            let stops = DayPlanner.plan(candidates: candidates, pace: .relaxed, interests: [.culture], anchor: origin)
            #expect(stops[0].candidate?.name == "Museum 1")
        }
    }
}
