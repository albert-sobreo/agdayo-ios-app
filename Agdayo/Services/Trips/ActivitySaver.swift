import CoreLocation
import Foundation
import SwiftData

/// The one place a new `Activity` gets inserted, pushed to Firestore (for
/// shared trips), and given an exchange-rate snapshot (when its cost is in a
/// different currency than the trip's). Shared by every flow that creates
/// activities in bulk (Plan My Day), so it
/// can't drift apart.
enum ActivitySaver {

    /// Where a new activity goes by default: an hour after `latest` (the trip's
    /// latest activity), on the same day unless that passes the trip's last
    /// day, or the trip's start when there are no activities yet.
    static func defaultDate(for trip: Trip, after latest: Date?) -> Date {
        guard let latest else { return trip.startDate }
        let next = latest.addingTimeInterval(60 * 60)
        let lastMoment = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: trip.endDate) ?? trip.endDate
        return min(next, lastMoment)
    }

    @MainActor
    @discardableResult
    static func insert(
        title: String,
        description: String = "",
        location: String,
        coordinate: CLLocationCoordinate2D?,
        date: Date,
        cost: Double = 0,
        costCurrency: String? = nil,
        iconName: String,
        trip: Trip,
        modelContext: ModelContext
    ) -> Activity {
        let hasCost = cost > 0
        let currencyCode = costCurrency ?? trip.currency
        let activity = Activity(
            title: title,
            activityDescription: description,
            location: location,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            date: date,
            cost: hasCost ? cost : nil,
            costCurrency: hasCost ? currencyCode : nil,
            iconName: iconName,
            trip: trip
        )
        modelContext.insert(activity)
        pushIfShared(activity, in: trip)
        if hasCost, currencyCode != trip.currency {
            applyExchangeRate(for: activity, from: currencyCode, in: trip)
        }
        return activity
    }

    /// Snapshots a conversion rate onto the activity so it still counts
    /// toward budget totals/balances (see `Activity.costAndRate`), which
    /// otherwise excludes any cost whose currency doesn't match the trip's
    /// and has no rate recorded.
    @MainActor
    private static func applyExchangeRate(for activity: Activity, from currencyCode: String, in trip: Trip) {
        let tripCurrency = trip.currency
        Task { @MainActor in
            guard let rate = await CurrencyConversionService.fetchRate(from: currencyCode, to: tripCurrency) else { return }
            activity.exchangeRateToTripCurrency = rate
            pushIfShared(activity, in: trip)
        }
    }

    @MainActor
    static func pushIfShared(_ activity: Activity, in trip: Trip) {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let activityID = activity.id
        let dto = activity.dto
        Task {
            try? await FirestoreCollectionSync.push(tripID: tripID, collection: "activities", docID: activityID, data: dto)
        }
    }
}
