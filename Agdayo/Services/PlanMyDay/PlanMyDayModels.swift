import CoreLocation
import Foundation

/// MapKit-free place categories, so the step logic can be tested with fake
/// candidates and the search layer maps these onto
/// `MKPointOfInterestCategory` separately.
enum PlaceKind: String, CaseIterable, Hashable {
    case landmark, museum, theater
    case park, beach, nationalPark
    case store
    case zoo, aquarium, amusementPark
    case foodMarket
    case nightlife
    case restaurant, cafe, bakery
    case spa, brewery, musicVenue, movieTheater
    case hiking, campground, waterSports, sports, recreation

    /// Shown in the UI ("National Park").
    var displayName: String {
        switch self {
        case .nationalPark: return "National Park"
        case .foodMarket: return "Food Market"
        case .amusementPark: return "Amusement Park"
        case .store: return "Shopping"
        case .landmark: return "Landmark"
        case .spa: return "Spa & Wellness"
        case .brewery: return "Craft Beer & Wine"
        case .musicVenue: return "Live Music"
        case .movieTheater: return "Cinema"
        case .hiking: return "Hiking"
        case .campground: return "Camping"
        case .waterSports: return "Water Sports"
        case .sports: return "Sports"
        case .recreation: return "Games & Fun"
        default: return rawValue.capitalized
        }
    }

    var isMeal: Bool {
        self == .restaurant || self == .cafe || self == .bakery
    }
}

enum Interest: String, CaseIterable, Identifiable, Hashable {
    case food, culture, nature, shopping, nightlife, family, wellness, adventure

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
        case .wellness: return "heart"
        case .adventure: return "figure.hiking"
        }
    }

    /// What this interest offers for the "what to do" steps.
    var activityKinds: [PlaceKind] {
        switch self {
        case .food: return [.foodMarket, .bakery, .brewery, .cafe]
        case .culture: return [.landmark, .museum, .theater, .musicVenue]
        case .nature: return [.park, .beach, .nationalPark, .hiking, .campground]
        case .shopping: return [.store, .foodMarket]
        case .nightlife: return [.nightlife, .brewery, .musicVenue]
        case .family: return [.zoo, .aquarium, .amusementPark, .recreation, .movieTheater]
        case .wellness: return [.spa, .park]
        case .adventure: return [.hiking, .waterSports, .recreation, .sports, .campground]
        }
    }

    /// Kinds for "what to do" steps; a sensible default when nothing sight-like is picked.
    static func activityKinds(for interests: Set<Interest>) -> [PlaceKind] {
        var kinds: [PlaceKind] = []
        for interest in Interest.allCases where interests.contains(interest) {
            for kind in interest.activityKinds where !kinds.contains(kind) { kinds.append(kind) }
        }
        return kinds.isEmpty ? [.landmark, .museum, .park] : kinds
    }
}

/// One step of the day the traveler walks through: breakfast, something to
/// do, lunch, and so on.
enum StepKind: String, Hashable {
    case breakfast, activity, lunch, coffee, dinner, evening

    var title: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .activity: return "Something to do"
        case .lunch: return "Lunch"
        case .coffee: return "Coffee break"
        case .dinner: return "Dinner"
        case .evening: return "Evening out"
        }
    }

    var iconName: String {
        switch self {
        case .breakfast: return "sunrise"
        case .activity: return "figure.walk"
        case .lunch: return "fork.knife"
        case .coffee: return "cup.and.saucer"
        case .dinner: return "fork.knife.circle"
        case .evening: return "moon.stars"
        }
    }

    /// What kinds of places this step offers.
    func placeKinds(for interests: Set<Interest>) -> [PlaceKind] {
        switch self {
        case .breakfast: return [.cafe, .bakery, .restaurant]
        case .lunch: return [.restaurant, .foodMarket, .cafe]
        case .dinner: return [.restaurant]
        case .coffee: return [.cafe, .bakery]
        case .evening: return [.nightlife, .brewery, .musicVenue, .theater, .restaurant]
        case .activity: return Interest.activityKinds(for: interests)
        }
    }
}

struct StepTemplate: Equatable {
    let kind: StepKind
    let hour: Int
    let minute: Int
}

enum Pace: String, CaseIterable, Identifiable, Hashable {
    case relaxed, balanced, packed

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    /// The day's steps and the time each starts at by default (the traveler
    /// can change any of them).
    var steps: [StepTemplate] {
        switch self {
        case .relaxed:
            return [
                StepTemplate(kind: .breakfast, hour: 9, minute: 0),
                StepTemplate(kind: .activity, hour: 10, minute: 30),
                StepTemplate(kind: .lunch, hour: 12, minute: 30),
                StepTemplate(kind: .activity, hour: 15, minute: 0),
                StepTemplate(kind: .dinner, hour: 18, minute: 30),
            ]
        case .balanced:
            return [
                StepTemplate(kind: .breakfast, hour: 8, minute: 0),
                StepTemplate(kind: .activity, hour: 9, minute: 30),
                StepTemplate(kind: .lunch, hour: 12, minute: 0),
                StepTemplate(kind: .activity, hour: 14, minute: 0),
                StepTemplate(kind: .coffee, hour: 16, minute: 0),
                StepTemplate(kind: .dinner, hour: 18, minute: 30),
            ]
        case .packed:
            return [
                StepTemplate(kind: .breakfast, hour: 7, minute: 30),
                StepTemplate(kind: .activity, hour: 9, minute: 0),
                StepTemplate(kind: .activity, hour: 10, minute: 45),
                StepTemplate(kind: .lunch, hour: 12, minute: 30),
                StepTemplate(kind: .activity, hour: 14, minute: 0),
                StepTemplate(kind: .coffee, hour: 16, minute: 0),
                StepTemplate(kind: .activity, hour: 17, minute: 0),
                StepTemplate(kind: .dinner, hour: 19, minute: 0),
                StepTemplate(kind: .evening, hour: 20, minute: 45),
            ]
        }
    }

    var summary: String {
        steps.map { $0.kind.title.lowercased() }.joined(separator: ", ")
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
    /// How prominent the place looks, roughly -1...1. MapKit has no ratings,
    /// so this is relevance-search rank minus a penalty for generic chains.
    /// 0 means "no signal".
    let prominence: Double
    /// Apple Maps' id for the place, used to load its full place card.
    let mapItemIdentifier: String?
    /// The city/town the place is in, as reported by MapKit.
    let city: String?

    init(
        id: UUID = UUID(),
        name: String,
        kind: PlaceKind,
        coordinate: CLLocationCoordinate2D,
        locality: String? = nil,
        prominence: Double = 0,
        mapItemIdentifier: String? = nil,
        city: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.locality = locality
        self.prominence = prominence
        self.mapItemIdentifier = mapItemIdentifier
        self.city = city
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Name-based identity — the same venue can come back from different
    /// searches under different ids.
    static func key(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Maps reports the same ward or city under several spellings
    /// ("Shinjuku", "Shinjuku-Ku", "新宿区", "中原区, 川崎市"). This reduces them
    /// to one key so a place isn't split into a group per spelling: last
    /// comma part, folded, with ward/city suffixes removed.
    static func cityKey(_ city: String?) -> String {
        guard let last = city?.split(separator: ",").last else { return "" }
        var key = String(last).trimmingCharacters(in: .whitespaces)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        for suffix in ["-ku", " ku", "-shi", " shi", " city", " ward", "区", "市", "町", "村"]
        where key.hasSuffix(suffix) && key.count > suffix.count {
            key.removeLast(suffix.count)
            break
        }
        return key.trimmingCharacters(in: .whitespaces)
    }

    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}

/// How a step's list of places is ordered.
enum StepSort: String, CaseIterable, Identifiable {
    case bestMatch, closest

    var id: String { rawValue }

    var title: String { self == .bestMatch ? "Best match" : "Closest" }
}
