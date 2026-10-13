import ActivityKit
import Foundation
import Observation

/// App-wide (same pattern as `LiveLocationSharingCoordinator`) so a running
/// Live Activity survives navigating away from the trip screen. Fully
/// local — no push token requested, no server involved, matching
/// `NotificationScheduler`'s on-device-only approach to reminders. Only one
/// trip's Live Activity runs at a time. See `TripLiveActivityAttributes`
/// for why its types are duplicated into the `AgdayoWidgets` extension
/// instead of shared via a framework target.
@MainActor
@Observable
final class TripLiveActivityCoordinator {
    private(set) var runningTripID: UUID?

    func isRunning(tripID: UUID) -> Bool {
        runningTripID == tripID
    }

    func start(trip: Trip, activities: [Activity]) {
        guard runningTripID != trip.id else {
            refresh(trip: trip, activities: activities)
            return
        }
        stop()
        let attributes = TripLiveActivityAttributes(
            tripID: trip.id.uuidString,
            tripName: trip.name,
            themeColorHex: String(format: "%06X", trip.theme.accentColorHex)
        )
        let state = Self.contentState(trip: trip, activities: activities)
        do {
            _ = try Activity<TripLiveActivityAttributes>.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            runningTripID = trip.id
        } catch {
            // Live Activities aren't essential to using the app (e.g. a
            // person can disable them system-wide) — failing to start one
            // just means no Lock Screen/Dynamic Island card shows.
        }
    }

    /// Recomputes and pushes the current/next-activity state to whichever
    /// Live Activity is running for this trip. Called opportunistically —
    /// on every app foreground and whenever the trip's itinerary is viewed
    /// — since there's no server to push updates while backgrounded.
    func refresh(trip: Trip, activities: [Activity]) {
        guard runningTripID == trip.id else { return }
        let state = Self.contentState(trip: trip, activities: activities)
        let tripIDString = trip.id.uuidString
        Task {
            for activity in Activity<TripLiveActivityAttributes>.activities where activity.attributes.tripID == tripIDString {
                await activity.update(.init(state: state, staleDate: nil))
            }
        }
    }

    func stop() {
        guard let runningTripID else { return }
        let tripIDString = runningTripID.uuidString
        Task {
            for activity in Activity<TripLiveActivityAttributes>.activities where activity.attributes.tripID == tripIDString {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        self.runningTripID = nil
    }

    /// Called on every app foreground (`RootTabView`'s scenePhase hook).
    /// Restarts a trip's Live Activity if it's still active but expired
    /// under the system's 8h Dynamic Island / 12h Lock Screen cap (the
    /// user never explicitly turned it off), and reconciles `runningTripID`
    /// if a Live Activity is unexpectedly still/no-longer running.
    func reconcile(trip: Trip, activities: [Activity]) {
        let stillRunning = Activity<TripLiveActivityAttributes>.activities.contains { $0.attributes.tripID == trip.id.uuidString }
        if runningTripID == trip.id, !stillRunning {
            start(trip: trip, activities: activities)
        } else if stillRunning {
            runningTripID = trip.id
            refresh(trip: trip, activities: activities)
        }
    }

    /// "Current" = the latest activity today that's already started;
    /// "next" = the earliest one still ahead today. Deliberately scoped to
    /// today only — crossing into tomorrow would need a "Day N" label
    /// change mid-activity, which isn't worth the complexity for v1.
    private static func contentState(trip: Trip, activities: [Activity]) -> TripLiveActivityAttributes.ContentState {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let todaysActivities = activities
            .filter { calendar.isDate($0.date, inSameDayAs: today) }
            .sorted { $0.date < $1.date }

        let now = Date()
        let current = todaysActivities.last { $0.date <= now }
        let next = todaysActivities.first { $0.date > now }

        let dayNumber = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: trip.startDate), to: today).day ?? 0) + 1)

        return TripLiveActivityAttributes.ContentState(
            dayLabel: "Day \(dayNumber)",
            currentActivityName: current?.title,
            currentActivityLocation: (current?.location.isEmpty == false) ? current?.location : nil,
            nextActivityName: next?.title,
            nextActivityLocation: (next?.location.isEmpty == false) ? next?.location : nil,
            nextActivityStartDate: next?.date
        )
    }
}
