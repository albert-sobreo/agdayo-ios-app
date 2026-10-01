import Foundation
import SwiftData

/// A standalone purchase made during a trip that isn't tied to any
/// Activity/Accommodation/Transport — e.g. a souvenir or a snack bought on
/// the go. Otherwise mirrors those types' cost-tracking fields exactly
/// (currency + exchange rate, paid-by + split) so it rolls into the same
/// Budget page totals and `ExpenseBalanceService` settle-up math.
@Model
final class Expense {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Both optional and independent — a purchase might only be
    /// remembered by day, only by time of day, both, or neither.
    var date: Date?
    var time: String?
    var cost: Double
    var costCurrency: String?
    /// Snapshot of the rate to the trip's currency at the moment `cost` was
    /// entered — see `Activity.exchangeRateToTripCurrency`.
    var exchangeRateToTripCurrency: Double?
    /// Exactly one of `budgetCategoryID`/`budgetMemberUID` is set — see
    /// `Activity.budgetCategoryID`/`budgetMemberUID`. Mandatory at the UI
    /// layer (`ExpenseEditSheet.isValid`), unlike the other expense types.
    var budgetCategoryID: UUID?
    var budgetMemberUID: String?
    var paidByUID: String?
    var splitUIDs: [String] = []
    var splitAmounts: [String: Double] = [:]
    var trip: Trip?

    init(
        id: UUID = UUID(),
        name: String,
        date: Date? = nil,
        time: String? = nil,
        cost: Double = 0,
        costCurrency: String? = nil,
        exchangeRateToTripCurrency: Double? = nil,
        budgetCategoryID: UUID? = nil,
        budgetMemberUID: String? = nil,
        paidByUID: String? = nil,
        splitUIDs: [String] = [],
        splitAmounts: [String: Double] = [:],
        trip: Trip? = nil
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.time = time
        self.cost = cost
        self.costCurrency = costCurrency
        self.exchangeRateToTripCurrency = exchangeRateToTripCurrency
        self.budgetCategoryID = budgetCategoryID
        self.budgetMemberUID = budgetMemberUID
        self.paidByUID = paidByUID
        self.splitUIDs = splitUIDs
        self.splitAmounts = splitAmounts
        self.trip = trip
    }

    /// Same idea as `Activity.costAndRate(inTripCurrency:)`.
    func costAndRate(inTripCurrency tripCurrency: String) -> (cost: Double, rate: Double)? {
        if costCurrency == nil || costCurrency == tripCurrency { return (cost, 1) }
        guard let exchangeRateToTripCurrency else { return nil }
        return (cost * exchangeRateToTripCurrency, exchangeRateToTripCurrency)
    }

    /// Combines `date` + `time` ("HH:mm") into one instant, when both are
    /// set. `nil` when there's no date at all — a bare time with nothing to
    /// anchor it to can't be placed on the trip's calendar.
    var dateTime: Date? {
        guard let date else { return nil }
        guard let time else { return date }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return date }
        return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date) ?? date
    }
}
