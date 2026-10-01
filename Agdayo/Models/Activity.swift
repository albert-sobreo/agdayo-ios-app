import Foundation
import SwiftData
import CoreLocation

@Model
final class Activity {
    @Attribute(.unique) var id: UUID
    var title: String
    var activityDescription: String
    var location: String
    var latitude: Double?
    var longitude: Double?
    var date: Date
    var cost: Double?
    var costCurrency: String?
    var costNote: String?
    /// Snapshot of the rate to the trip's currency at the moment `cost` was
    /// entered (1 `costCurrency` = this many of the trip's currency). `nil`
    /// when `costCurrency` matches the trip's own, or when no rate could be
    /// captured yet (offline entry with no manual override) — in the latter
    /// case totals fall back to excluding this cost rather than guessing.
    var exchangeRateToTripCurrency: Double?
    var iconName: String
    /// Which planned budget category this expense counts against, if any —
    /// purely for the Budget page's planned-vs-actual breakdown, not used
    /// in `costAndRate`/split logic.
    var budgetCategoryID: UUID?
    /// Alternative to `budgetCategoryID` — attaches this expense to a
    /// member's individual budget instead of a category. At most one of
    /// the two is ever set; the Budget page's picker clears the other when
    /// you pick one.
    var budgetMemberUID: String?
    var paidByUID: String?
    var splitUIDs: [String] = []
    /// Custom per-member share amounts, keyed by uid. Empty means "split
    /// `splitUIDs` evenly" — only populated when someone paid unequal
    /// amounts (e.g. ordered different things at a shared meal).
    var splitAmounts: [String: Double] = [:]
    /// This device's EventKit event identifier, if the activity has been
    /// added to Calendar — deliberately NOT part of `ActivityDTO`/synced.
    /// Each member's calendar is their own; adding it on one device
    /// shouldn't add it (or an unrelated identifier) on another's.
    var calendarEventID: String?
    var trip: Trip?

    init(
        id: UUID = UUID(),
        title: String,
        activityDescription: String = "",
        location: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        date: Date = .now,
        cost: Double? = nil,
        costCurrency: String? = nil,
        costNote: String? = nil,
        exchangeRateToTripCurrency: Double? = nil,
        iconName: String = "mappin.and.ellipse",
        budgetCategoryID: UUID? = nil,
        budgetMemberUID: String? = nil,
        paidByUID: String? = nil,
        splitUIDs: [String] = [],
        splitAmounts: [String: Double] = [:],
        calendarEventID: String? = nil,
        trip: Trip? = nil
    ) {
        self.id = id
        self.title = title
        self.activityDescription = activityDescription
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.date = date
        self.cost = cost
        self.costCurrency = costCurrency
        self.costNote = costNote
        self.exchangeRateToTripCurrency = exchangeRateToTripCurrency
        self.iconName = iconName
        self.budgetCategoryID = budgetCategoryID
        self.budgetMemberUID = budgetMemberUID
        self.paidByUID = paidByUID
        self.splitUIDs = splitUIDs
        self.splitAmounts = splitAmounts
        self.calendarEventID = calendarEventID
        self.trip = trip
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// `cost` converted into the trip's currency using the snapshotted
    /// exchange rate, plus that rate itself (1 when currencies already
    /// match) — the rate is needed by `ExpenseBalanceService` to also
    /// convert any custom per-person `splitAmounts`, which are entered in
    /// this activity's own currency. `nil` when the currencies differ and
    /// no rate was ever captured, so totals/balances safely exclude it
    /// rather than guessing.
    func costAndRate(inTripCurrency tripCurrency: String) -> (cost: Double, rate: Double)? {
        guard let cost else { return nil }
        if costCurrency == nil || costCurrency == tripCurrency { return (cost, 1) }
        guard let exchangeRateToTripCurrency else { return nil }
        return (cost * exchangeRateToTripCurrency, exchangeRateToTripCurrency)
    }
}
