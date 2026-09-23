import Foundation
import UserNotifications

/// Local, on-device reminders for upcoming activities and transport
/// departures — scheduled purely from data already synced to this device.
/// No server, push entitlement, or paid Apple Developer enrollment needed
/// (unlike the dormant WeatherKit feature). Each reminder's identifier is
/// derived from the model's own id, so re-scheduling (an edit, or a change
/// synced in from another member) replaces the pending request instead of
/// duplicating it.
enum NotificationScheduler {
    /// Backs the "Trip Reminders" toggle in `ProfileView`. Reads/writes the
    /// same `UserDefaults` key an `@AppStorage` there binds to, so flipping
    /// the toggle takes effect immediately without needing this enum to
    /// observe anything.
    static let remindersEnabledKey = "remindersEnabled"

    private static let activityLeadTime: TimeInterval = 15 * 60 // 15 minutes before
    private static let transportLeadTime: TimeInterval = 60 * 60 // 1 hour before

    static var remindersEnabled: Bool {
        (UserDefaults.standard.object(forKey: remindersEnabledKey) as? Bool) ?? true
    }

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    /// Cancels every pending reminder outright — called when the "Trip
    /// Reminders" toggle is switched off.
    static func cancelAllReminders() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Re-schedules a reminder for every upcoming activity/transport segment
    /// across every trip — called when the toggle is switched back on, since
    /// nothing was tracked individually while it was off.
    static func rescheduleAllReminders(trips: [Trip]) {
        for trip in trips {
            for activity in trip.activities {
                scheduleReminder(for: activity)
            }
            for segment in trip.transportSegments {
                scheduleReminder(for: segment)
            }
        }
    }

    static func scheduleReminder(for activity: Activity) {
        let identifier = activityIdentifier(activity.id)
        cancel(identifiers: [identifier])
        guard remindersEnabled, let fireDate = fireDate(for: activity.date, leadTime: activityLeadTime) else { return }

        let content = UNMutableNotificationContent()
        content.title = activity.title
        content.body = activity.location.isEmpty
            ? "Starting in 15 minutes"
            : "Starting in 15 minutes, at \(activity.location)"
        content.sound = .default
        schedule(identifier: identifier, content: content, fireDate: fireDate)
    }

    static func cancelReminder(forActivityID id: UUID) {
        cancel(identifiers: [activityIdentifier(id)])
    }

    static func scheduleReminder(for segment: TransportSegment) {
        let identifier = transportIdentifier(segment.id)
        cancel(identifiers: [identifier])
        guard remindersEnabled, let fireDate = fireDate(for: segment.departureDateTime, leadTime: transportLeadTime) else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(segment.mode.displayName) departs in an hour"
        content.body = segment.departureLocation.isEmpty
            ? "Don't forget to head out"
            : "From \(segment.departureLocation)"
        content.sound = .default
        schedule(identifier: identifier, content: content, fireDate: fireDate)
    }

    static func cancelReminder(forTransportID id: UUID) {
        cancel(identifiers: [transportIdentifier(id)])
    }

    private static func fireDate(for date: Date, leadTime: TimeInterval) -> Date? {
        let fireDate = date.addingTimeInterval(-leadTime)
        return fireDate > .now ? fireDate : nil
    }

    private static func schedule(identifier: String, content: UNMutableNotificationContent, fireDate: Date) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func cancel(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func activityIdentifier(_ id: UUID) -> String { "activity-\(id.uuidString)" }
    private static func transportIdentifier(_ id: UUID) -> String { "transport-\(id.uuidString)" }
}
