import Foundation

struct ExpenseSettlement: Identifiable {
    var id: String { "\(fromUID)-\(toUID)" }
    let fromUID: String
    let toUID: String
    let amount: Double
}

/// Aggregates "who paid" / "who's splitting" across Activities,
/// Accommodations, TransportSegments, and custom Expenses (never
/// BudgetCategories — those are planning estimates, not a payment anyone
/// actually made) into net per-member balances and a minimal settle-up
/// list. Pure functions, no persistence — always recomputed from the
/// caller's current data.
///
/// Takes explicit arrays rather than a `Trip` so callers can supply
/// `@Query`-sourced, live-updating arrays (see `BalancesView`) instead of
/// `trip.activities`-style relationship traversals, which don't reliably
/// refresh when a child screen inserts a new item on the inverse side.
enum ExpenseBalanceService {
    private struct SplittableCost {
        let amount: Double
        let paidByUID: String
        /// uid -> amount owed, summing to `amount` — either an even split
        /// across `splitUIDs`, or the item's custom `splitAmounts` when
        /// someone paid unequal shares (e.g. ordered different things at a
        /// shared meal).
        let shares: [String: Double]
    }

    /// Positive balance = that member is owed money overall; negative =
    /// they owe money overall. Recorded `Settlement`s (real payments members
    /// have already made to each other) net against the raw expense
    /// imbalance, so a paid-back debt disappears from here and from the
    /// settle-up suggestions below.
    static func balances(
        activities: [Activity],
        accommodations: [Accommodation],
        transportSegments: [TransportSegment],
        expenses: [Expense],
        recordedSettlements: [Settlement],
        currency: String,
        memberUIDs: Set<String> = []
    ) -> [String: Double] {
        var net: [String: Double] = [:]
        for item in splittableCosts(activities: activities, accommodations: accommodations, transportSegments: transportSegments, expenses: expenses, currency: currency, memberUIDs: memberUIDs) {
            net[item.paidByUID, default: 0] += item.amount
            for (uid, share) in item.shares {
                net[uid, default: 0] -= share
            }
        }
        for settlement in recordedSettlements {
            net[settlement.fromUID, default: 0] += settlement.amount
            net[settlement.toUID, default: 0] -= settlement.amount
        }
        return net
    }

    /// Classic greedy debt-simplification: repeatedly match the largest
    /// creditor with the largest debtor so members see the minimum number
    /// of payments needed, rather than one line per underlying expense.
    static func settlements(
        activities: [Activity],
        accommodations: [Accommodation],
        transportSegments: [TransportSegment],
        expenses: [Expense],
        recordedSettlements: [Settlement],
        currency: String,
        memberUIDs: Set<String> = []
    ) -> [ExpenseSettlement] {
        let net = balances(activities: activities, accommodations: accommodations, transportSegments: transportSegments, expenses: expenses, recordedSettlements: recordedSettlements, currency: currency, memberUIDs: memberUIDs)
        var creditors = net
            .filter { $0.value > 0.01 }
            .map { $0 }
            .sorted { $0.value > $1.value }
        var debtors = net
            .filter { $0.value < -0.01 }
            .map { (key: $0.key, value: -$0.value) }
            .sorted { $0.value > $1.value }

        var results: [ExpenseSettlement] = []
        var ci = 0
        var di = 0
        while ci < creditors.count && di < debtors.count {
            let amount = min(creditors[ci].value, debtors[di].value)
            if amount > 0.01 {
                results.append(ExpenseSettlement(fromUID: debtors[di].key, toUID: creditors[ci].key, amount: amount))
            }
            creditors[ci].value -= amount
            debtors[di].value -= amount
            if creditors[ci].value <= 0.01 { ci += 1 }
            if debtors[di].value <= 0.01 { di += 1 }
        }
        return results
    }

    /// Costs in a different currency than the trip's are converted using
    /// each item's snapshotted exchange rate (see `Activity`/
    /// `TransportSegment.costAndRate(inTripCurrency:)`) — only excluded if
    /// no rate was ever captured. Accommodations have no currency field of
    /// their own, so they always count as-is.
    private static func splittableCosts(
        activities: [Activity],
        accommodations: [Accommodation],
        transportSegments: [TransportSegment],
        expenses: [Expense],
        currency: String,
        memberUIDs: Set<String>
    ) -> [SplittableCost] {
        var items: [SplittableCost] = []

        for activity in activities {
            guard let (cost, rate) = activity.costAndRate(inTripCurrency: currency), cost > 0,
                  let paidByUID = activity.paidByUID,
                  !activity.splitUIDs.isEmpty else { continue }
            items.append(SplittableCost(amount: cost, paidByUID: paidByUID, shares: shares(amount: cost, splitUIDs: activity.splitUIDs, splitAmounts: activity.splitAmounts, rate: rate, memberUIDs: memberUIDs)))
        }

        for accommodation in accommodations {
            guard accommodation.totalCost > 0,
                  let paidByUID = accommodation.paidByUID,
                  !accommodation.splitUIDs.isEmpty else { continue }
            items.append(SplittableCost(amount: accommodation.totalCost, paidByUID: paidByUID, shares: shares(amount: accommodation.totalCost, splitUIDs: accommodation.splitUIDs, splitAmounts: accommodation.splitAmounts, rate: 1, memberUIDs: memberUIDs)))
        }

        for segment in transportSegments {
            guard let (cost, rate) = segment.costAndRate(inTripCurrency: currency), cost > 0,
                  let paidByUID = segment.paidByUID,
                  !segment.splitUIDs.isEmpty else { continue }
            items.append(SplittableCost(amount: cost, paidByUID: paidByUID, shares: shares(amount: cost, splitUIDs: segment.splitUIDs, splitAmounts: segment.splitAmounts, rate: rate, memberUIDs: memberUIDs)))
        }

        for expense in expenses {
            guard let (cost, rate) = expense.costAndRate(inTripCurrency: currency), cost > 0,
                  let paidByUID = expense.paidByUID,
                  !expense.splitUIDs.isEmpty else { continue }
            items.append(SplittableCost(amount: cost, paidByUID: paidByUID, shares: shares(amount: cost, splitUIDs: expense.splitUIDs, splitAmounts: expense.splitAmounts, rate: rate, memberUIDs: memberUIDs)))
        }

        return items
    }

    /// `splitAmounts` (custom, unequal shares) takes priority when present;
    /// otherwise divides `amount` evenly across `splitUIDs`. Custom amounts
    /// are entered in the item's own currency, so `rate` (1 when currencies
    /// already match) converts them the same way `amount` was converted.
    ///
    /// `memberUIDs` is the trip's current members (empty when unknown). Anyone
    /// in the split who has since been removed from the trip is left out, and
    /// the cost is shared among the people still in it, so the shares always
    /// add up to the cost. Custom amounts no longer add up once someone is
    /// left out, so the cost is then split evenly instead.
    static func shares(amount: Double, splitUIDs: [String], splitAmounts: [String: Double], rate: Double, memberUIDs: Set<String> = []) -> [String: Double] {
        var uids = splitUIDs
        var custom = splitAmounts
        if !memberUIDs.isEmpty {
            let current = splitUIDs.filter { memberUIDs.contains($0) }
            if !current.isEmpty, current.count != splitUIDs.count {
                uids = current
                custom = [:]
            }
        }
        guard custom.isEmpty else {
            return uids.reduce(into: [:]) { result, uid in
                result[uid] = (custom[uid] ?? 0) * rate
            }
        }
        let evenShare = amount / Double(uids.count)
        return Dictionary(uids.map { ($0, evenShare) }, uniquingKeysWith: { first, _ in first })
    }

    /// The people splitting an item, leaving out anyone no longer on the trip
    /// (falls back to everyone listed if that would leave nobody).
    static func currentSplitUIDs(_ splitUIDs: [String], memberUIDs: Set<String>) -> [String] {
        guard !memberUIDs.isEmpty else { return splitUIDs }
        let current = splitUIDs.filter { memberUIDs.contains($0) }
        return current.isEmpty ? splitUIDs : current
    }

    /// An even share per person, rounded to the cent, with the cents left over
    /// from rounding given to the last person so the shares add up exactly to
    /// `total` (e.g. 100 for 3 people is 33.33, 33.33, 33.34).
    static func roundedEvenShares(total: Double, uids: [String]) -> [String: Double] {
        guard !uids.isEmpty else { return [:] }
        let ordered = uids.sorted()
        let share = (total / Double(ordered.count) * 100).rounded(.down) / 100
        var result: [String: Double] = [:]
        for uid in ordered.dropLast() { result[uid] = share }
        let rest = total - share * Double(ordered.count - 1)
        result[ordered[ordered.count - 1]] = (rest * 100).rounded() / 100
        return result
    }
}
