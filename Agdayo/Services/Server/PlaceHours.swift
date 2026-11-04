import Foundation

/// A place's weekly opening hours from Google (through the Agdayo server),
/// for warning when an activity is planned while the place is closed.
/// Mirrors `openingPeriods` and `utcOffsetMinutes` in worker/src/google.ts.
struct PlaceHours: Codable, Equatable {
    struct Time: Codable, Equatable {
        /// 0 is Sunday, in the place's local time.
        let day: Int
        let hour: Int
        let minute: Int

        var minuteOfWeek: Int { day * 1440 + hour * 60 + minute }
    }

    struct Period: Codable, Equatable {
        let open: Time
        /// Nil means open around the clock.
        let close: Time?
    }

    let periods: [Period]
    /// The place's offset from UTC. Nil falls back to the phone's time zone.
    let utcOffsetMinutes: Int?

    /// Whether the place is open at that moment, or nil when Google gave no hours.
    func isOpen(at date: Date) -> Bool? {
        guard !periods.isEmpty else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        if let utcOffsetMinutes, let zone = TimeZone(secondsFromGMT: utcOffsetMinutes * 60) {
            calendar.timeZone = zone
        }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let minute = ((parts.weekday ?? 1) - 1) * 1440 + (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        for period in periods {
            guard let close = period.close else { return true }
            let start = period.open.minuteOfWeek, end = close.minuteOfWeek
            // A period can run past Saturday midnight into Sunday.
            let open = end > start ? (start..<end).contains(minute) : (minute >= start || minute < end)
            if open { return true }
        }
        return false
    }
}

/// Opening hours kept on the phone for a week, so the itinerary doesn't ask
/// Google again every time it's opened (and still works offline).
enum PlaceHoursStore {
    private struct Entry: Codable {
        let hours: PlaceHours
        let fetchedAt: Date
    }

    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60
    private static let key = "placeHours.v1"

    /// Hours for a Google place ID, from the phone if fresh, else from the server.
    /// Nil when unknown (no hours, offline with nothing saved, or not signed in).
    @MainActor
    static func hours(for placeID: String) async -> PlaceHours? {
        var saved = load()
        if let entry = saved[placeID], Date.now.timeIntervalSince(entry.fetchedAt) < maxAge {
            return entry.hours
        }
        guard let fresh = try? await AgdayoServer.placeHours(id: placeID) else {
            return saved[placeID]?.hours
        }
        saved[placeID] = Entry(hours: fresh, fetchedAt: .now)
        store(saved)
        return fresh
    }

    private static func load() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private static func store(_ entries: [String: Entry]) {
        let fresh = entries.filter { Date.now.timeIntervalSince($0.value.fetchedAt) < maxAge }
        if let data = try? JSONEncoder().encode(fresh) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
