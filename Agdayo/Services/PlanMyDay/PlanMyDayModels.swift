import CoreLocation
import Foundation

/// MapKit-free place categories, so `DayPlanner` can be tested with fake
/// candidates and the search layer can map these onto
/// `MKPointOfInterestCategory` separately.
enum PlaceKind: String, CaseIterable, Hashable {
    case museum, theater
    case park, beach, nationalPark
    case store
    case zoo, aquarium, amusementPark
    case foodMarket
    case nightlife
    case restaurant, cafe, bakery
}

enum Interest: String, CaseIterable, Identifiable, Hashable {
    case food, culture, nature, shopping, nightlife, family

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var iconName: String {
        switch self {
        case .food: return "fork.knife"
        case .culture: return "building.columns"
        case .nature: return "leaf"
        case .shopping: return "bag"
        case .nightlife: return "moon.stars"
        case .family: return "figure.2.and.child.holdinghands"
        }
    }

    /// What this interest contributes to "Sight" slots. Nightlife is empty on
    /// purpose — it only feeds the evening slot.
    var sightKinds: [PlaceKind] {
        switch self {
        case .food: return [.foodMarket]
        case .culture: return [.museum, .theater]
        case .nature: return [.park, .beach, .nationalPark]
        case .shopping: return [.store]
        case .nightlife: return []
        case .family: return [.zoo, .aquarium, .amusementPark]
        }
    }
}

enum SlotKind: Hashable {
    case sight, lunch, dinner, coffee, evening
}

struct SlotTemplate: Equatable {
    let kind: SlotKind
    let hour: Int
    let minute: Int
}

enum Pace: String, CaseIterable, Identifiable, Hashable {
    case relaxed, balanced, packed

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var slots: [SlotTemplate] {
        switch self {
        case .relaxed:
            return [
                SlotTemplate(kind: .sight, hour: 10, minute: 0),
                SlotTemplate(kind: .lunch, hour: 12, minute: 30),
                SlotTemplate(kind: .dinner, hour: 18, minute: 30),
            ]
        case .balanced:
            return [
                SlotTemplate(kind: .sight, hour: 9, minute: 30),
                SlotTemplate(kind: .lunch, hour: 12, minute: 0),
                SlotTemplate(kind: .sight, hour: 14, minute: 0),
                SlotTemplate(kind: .dinner, hour: 18, minute: 30),
            ]
        case .packed:
            return [
                SlotTemplate(kind: .sight, hour: 9, minute: 0),
                SlotTemplate(kind: .sight, hour: 10, minute: 45),
                SlotTemplate(kind: .lunch, hour: 12, minute: 30),
                SlotTemplate(kind: .sight, hour: 14, minute: 0),
                SlotTemplate(kind: .coffee, hour: 16, minute: 0),
                SlotTemplate(kind: .evening, hour: 18, minute: 30),
            ]
        }
    }
}

struct Candidate: Identifiable, Equatable {
    let id: UUID
    let name: String
    let kind: PlaceKind
    let latitude: Double
    let longitude: Double
    /// "Neighborhood, City" hint when MapKit has one.
    let locality: String?

    init(
        id: UUID = UUID(),
        name: String,
        kind: PlaceKind,
        coordinate: CLLocationCoordinate2D,
        locality: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.locality = locality
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct PlannedStop: Identifiable, Equatable {
    let id = UUID()
    let slotIndex: Int
    let slot: SlotTemplate
    /// `nil` when nothing matched the slot nearby — shown as "No match nearby."
    var candidate: Candidate?
}
