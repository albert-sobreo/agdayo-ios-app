import CoreLocation
import Foundation

/// What the Today card shows, worked out from the trip without any UI:
/// the next stop, where you'd be setting off from, and the rest of the day.
struct TodayPlan {
    /// The next activity that hasn't started yet: today's, or the next day's
    /// first when today is done.
    let next: Activity?
    /// Where you set off from when your location isn't known: the stop
    /// before `next` today, else the stay you're in.
    let fallbackOrigin: (name: String, coordinate: CLLocationCoordinate2D)?
    /// Today's activities after `next`.
    let laterToday: [Activity]
    /// True when `next` is on a later day than `now`.
    let nextIsTomorrowOrLater: Bool

    init(activities: [Activity], stays: [Accommodation], now: Date, calendar: Calendar = .current) {
        let sorted = activities.sorted { $0.date < $1.date }
        let upcoming = sorted.filter { $0.date > now }
        let next = upcoming.first
        self.next = next

        if let next {
            nextIsTomorrowOrLater = !calendar.isDate(next.date, inSameDayAs: now)
            laterToday = nextIsTomorrowOrLater
                ? []
                : upcoming.dropFirst().filter { calendar.isDate($0.date, inSameDayAs: now) }
            let previousToday = sorted.last {
                $0.date <= now && calendar.isDate($0.date, inSameDayAs: next.date) && $0.coordinate != nil
            }
            if let previousToday, let coordinate = previousToday.coordinate {
                fallbackOrigin = (previousToday.title, coordinate)
            } else if let stay = TravelPlanning.stay(for: next.date, in: stays, calendar: calendar), let coordinate = stay.coordinate {
                fallbackOrigin = (stay.name, coordinate)
            } else {
                fallbackOrigin = nil
            }
        } else {
            nextIsTomorrowOrLater = false
            laterToday = []
            fallbackOrigin = nil
        }
    }

    /// "Leave in 12 min", "Leave now" or "8 min late", and whether it's late.
    static func leaveText(leaveBy: Date, now: Date) -> (text: String, isLate: Bool) {
        let minutes = Int((leaveBy.timeIntervalSince(now) / 60).rounded(.down))
        if minutes > 90 {
            return ("Leave by \(leaveBy.formatted(date: .omitted, time: .shortened))", false)
        }
        if minutes >= 1 { return ("Leave in \(minutes) min", false) }
        if minutes >= -1 { return ("Leave now", false) }
        return ("\(-minutes) min late", true)
    }
}
