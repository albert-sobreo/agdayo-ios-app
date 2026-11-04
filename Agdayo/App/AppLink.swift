import Foundation

/// Addresses that open Agdayo from outside, e.g. from a link in a Claude chat.
///
///     agdayo://join?code=ABC123
///     agdayo://trip/<trip UUID>?day=2026-11-16
///
/// Claude's links point at the server's `/open/trip/...` page, which forwards
/// to the `agdayo://trip/...` form here.
enum AppLink: Equatable {
    case join(code: String?)
    /// `day` is the start of that day in `calendar`'s time zone.
    case trip(id: UUID, day: Date?)

    init?(url: URL, calendar: Calendar = .current) {
        guard url.scheme?.lowercased() == "agdayo",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        func query(_ name: String) -> String? {
            components.queryItems?.first(where: { $0.name.lowercased() == name })?.value
        }
        switch url.host?.lowercased() {
        case "join":
            self = .join(code: query("code"))
        case "trip":
            let segments = url.pathComponents.filter { $0 != "/" }
            guard let first = segments.first, let id = UUID(uuidString: first) else { return nil }
            self = .trip(id: id, day: query("day").flatMap { Self.day(from: $0, calendar: calendar) })
        default:
            return nil
        }
    }

    /// "2026-11-16" → the start of that date in `calendar`'s time zone.
    private static func day(from text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: date)
    }
}

/// A trip to open, and optionally the itinerary day to show.
struct TripLinkTarget: Equatable {
    let trip: Trip
    let day: Date?

    static func == (lhs: TripLinkTarget, rhs: TripLinkTarget) -> Bool {
        lhs.trip.id == rhs.trip.id && lhs.day == rhs.day
    }
}
