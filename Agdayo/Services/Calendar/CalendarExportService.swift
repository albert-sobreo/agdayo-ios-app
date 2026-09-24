import EventKit
import Foundation

/// Adds/removes Activities and TransportSegments as events in the user's
/// own Calendar app via EventKit. Deliberately a personal, per-device
/// action — the resulting event identifier is stored on
/// `Activity`/`TransportSegment.calendarEventID`, which is excluded from
/// their DTOs so it never syncs to other members.
enum CalendarExportService {
    private static let store = EKEventStore()

    static func requestAccessIfNeeded() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            return (try? await store.requestFullAccessToEvents()) ?? false
        default:
            return false
        }
    }

    /// Adds `activity` as a one-hour calendar event. Returns the event
    /// identifier to persist, or `nil` if access was denied or saving failed.
    static func addEvent(for activity: Activity) async -> String? {
        guard await requestAccessIfNeeded() else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = activity.title
        event.startDate = activity.date
        event.endDate = activity.date.addingTimeInterval(60 * 60)
        event.location = activity.location.isEmpty ? nil : activity.location
        event.notes = activity.activityDescription.isEmpty ? nil : activity.activityDescription
        event.calendar = store.defaultCalendarForNewEvents
        do {
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    /// Adds `segment` as a calendar event spanning departure to arrival
    /// (or a 2-hour default if no arrival details were entered).
    static func addEvent(for segment: TransportSegment) async -> String? {
        guard await requestAccessIfNeeded() else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = "\(segment.mode.displayName): \(segment.departureLocation) → \(segment.arrivalLocation)"
        event.startDate = segment.departureDateTime
        event.endDate = segment.arrivalDateTime ?? segment.departureDateTime.addingTimeInterval(2 * 60 * 60)
        event.location = segment.departureLocation.isEmpty ? nil : segment.departureLocation

        var notesLines: [String] = []
        if let bookingRef = segment.bookingRef, !bookingRef.isEmpty { notesLines.append("Booking: \(bookingRef)") }
        if let seatNumber = segment.seatNumber, !seatNumber.isEmpty { notesLines.append("Seat: \(seatNumber)") }
        event.notes = notesLines.isEmpty ? nil : notesLines.joined(separator: "\n")
        event.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            return nil
        }
    }

    /// Removes a previously-added event. No-ops if it can't be found (e.g.
    /// already deleted from the Calendar app directly).
    static func removeEvent(identifier: String) async {
        guard await requestAccessIfNeeded(), let event = store.event(withIdentifier: identifier) else { return }
        try? store.remove(event, span: .thisEvent)
    }
}
