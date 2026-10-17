import CoreLocation
import Foundation

/// Pure planning logic for "Plan my day": no MapKit, no network, no state —
/// takes candidates, a pace's slots, and an anchor, and returns stops. Kept
/// independent of the search layer so the data source can change without
/// touching this, and so it's unit-testable with fake candidates.
enum DayPlanner {

    static let nearRadius: CLLocationDistance = 2_000
    static let farRadius: CLLocationDistance = 4_000
    static let clusterRadius: CLLocationDistance = 1_000

    // MARK: Slot → place kinds

    static func kinds(for slot: SlotKind, interests: Set<Interest>) -> [PlaceKind] {
        switch slot {
        case .sight:
            let union = interests.flatMap(\.sightKinds)
            return union.isEmpty ? [.museum, .park] : Array(Set(union))
        case .lunch, .dinner:
            return [.restaurant]
        case .coffee:
            return [.cafe, .bakery]
        case .evening:
            return interests.contains(.nightlife) ? [.restaurant, .nightlife] : [.restaurant]
        }
    }

    /// Every kind the search layer needs to fetch for this pace + interests.
    static func requiredKinds(pace: Pace, interests: Set<Interest>) -> Set<PlaceKind> {
        Set(pace.slots.flatMap { kinds(for: $0.kind, interests: interests) })
    }

    // MARK: Anchor

    /// The hotel/trip anchor when there is one; otherwise the candidate with
    /// the most other candidates within `clusterRadius` (the "center of
    /// things" — a better start than an arbitrary pin).
    static func chooseAnchor(
        candidates: [Candidate],
        preferred: CLLocationCoordinate2D?
    ) -> CLLocationCoordinate2D? {
        if let preferred { return preferred }
        var best: (candidate: Candidate, neighbors: Int)?
        for candidate in candidates {
            let neighbors = candidates.filter {
                $0.id != candidate.id
                    && distance(from: candidate.coordinate, to: $0.coordinate) <= clusterRadius
            }.count
            if best == nil || neighbors > best!.neighbors {
                best = (candidate, neighbors)
            }
        }
        return best?.candidate.coordinate
    }

    // MARK: Planning

    /// Greedy nearest-neighbor fill. Each slot takes the nearest unused
    /// matching place within `nearRadius` of the previous stop, widening to
    /// `farRadius`, else stays empty. `topChoices > 1` picks randomly among
    /// that many nearest instead (Shuffle) — variety without losing a
    /// compact route.
    static func plan<G: RandomNumberGenerator>(
        candidates: [Candidate],
        pace: Pace,
        interests: Set<Interest>,
        anchor: CLLocationCoordinate2D,
        excludedNames: Set<String> = [],
        topChoices: Int = 1,
        using generator: inout G
    ) -> [PlannedStop] {
        var used = Set(excludedNames.map(key))
        var previous = anchor
        var stops: [PlannedStop] = []

        for (index, slot) in pace.slots.enumerated() {
            let allowed = Set(kinds(for: slot.kind, interests: interests))
            let pool = candidates.filter { allowed.contains($0.kind) && !used.contains(key($0.name)) }
            let pick = choose(from: pool, near: previous, topChoices: topChoices, using: &generator)
            if let pick {
                used.insert(key(pick.name))
                previous = pick.coordinate
            }
            stops.append(PlannedStop(slotIndex: index, slot: slot, candidate: pick))
        }
        return stops
    }

    static func plan(
        candidates: [Candidate],
        pace: Pace,
        interests: Set<Interest>,
        anchor: CLLocationCoordinate2D,
        excludedNames: Set<String> = [],
        topChoices: Int = 1
    ) -> [PlannedStop] {
        var generator = SystemRandomNumberGenerator()
        return plan(
            candidates: candidates, pace: pace, interests: interests, anchor: anchor,
            excludedNames: excludedNames, topChoices: topChoices, using: &generator
        )
    }

    // MARK: Helpers

    private static func choose<G: RandomNumberGenerator>(
        from pool: [Candidate],
        near point: CLLocationCoordinate2D,
        topChoices: Int,
        using generator: inout G
    ) -> Candidate? {
        for radius in [nearRadius, farRadius] {
            let within = pool
                .map { (candidate: $0, distance: distance(from: point, to: $0.coordinate)) }
                .filter { $0.distance <= radius }
                .sorted { $0.distance < $1.distance }
            if !within.isEmpty {
                let top = within.prefix(max(1, topChoices))
                return top.randomElement(using: &generator)?.candidate
            }
        }
        return nil
    }

    /// Name-based identity for "already used" checks — the same venue can come
    /// back from different category searches under different ids.
    static func key(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
