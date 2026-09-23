import Foundation

struct ExpenseSettlement: Identifiable {
    var id: String { "\(fromUID)-\(toUID)" }
    let fromUID: String
    let toUID: String
    let amount: Double
}

/// Aggregates "who paid" / "who's splitting" across Activities,
/// Accommodations, and TransportSegments (never BudgetCategories — those
/// are planning estimates, not a payment anyone actually made) into net
/// per-member balances and a minimal settle-up list. Pure functions, no
/// persistence — this is always recomputed from the trip's current data.
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
    static func balances(for trip: Trip) -> [String: Double] {
        var net: [String: Double] = [:]
        for item in splittableCosts(for: trip) {
            net[item.paidByUID, default: 0] += item.amount
            for (uid, share) in item.shares {
                net[uid, default: 0] -= share
            }
        }
        for settlement in trip.settlements {
            net[settlement.fromUID, default: 0] += settlement.amount
            net[settlement.toUID, default: 0] -= settlement.amount
        }
        return net
    }

    /// Classic greedy debt-simplification: repeatedly match the largest
    /// creditor with the largest debtor so members see the minimum number
    /// of payments needed, rather than one line per underlying expense.
    static func settlements(for trip: Trip) -> [ExpenseSettlement] {
        var creditors = balances(for: trip)
            .filter { $0.value > 0.01 }
            .map { $0 }
            .sorted { $0.value > $1.value }
        var debtors = balances(for: trip)
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
    private static func splittableCosts(for trip: Trip) -> [SplittableCost] {
        var items: [SplittableCost] = []

        for activity in trip.activities {
            guard let (cost, rate) = activity.costAndRate(inTripCurrency: trip.currency), cost > 0,
                  let paidByUID = activity.paidByUID,
                  !activity.splitUIDs.isEmpty else { continue }
            items.append(SplittableCost(amount: cost, paidByUID: paidByUID, shares: shares(amount: cost, splitUIDs: activity.splitUIDs, splitAmounts: activity.splitAmounts, rate: rate)))
        }

        for accommodation in trip.accommodations {
            guard accommodation.totalCost > 0,
                  let paidByUID = accommodation.paidByUID,
                  !accommodation.splitUIDs.isEmpty else { continue }
            items.append(SplittableCost(amount: accommodation.totalCost, paidByUID: paidByUID, shares: shares(amount: accommodation.totalCost, splitUIDs: accommodation.splitUIDs, splitAmounts: accommodation.splitAmounts, rate: 1)))
        }

        for segment in trip.transportSegments {
            guard let (cost, rate) = segment.costAndRate(inTripCurrency: trip.currency), cost > 0,
                  let paidByUID = segment.paidByUID,
                  !segment.splitUIDs.isEmpty else { continue }
            items.append(SplittableCost(amount: cost, paidByUID: paidByUID, shares: shares(amount: cost, splitUIDs: segment.splitUIDs, splitAmounts: segment.splitAmounts, rate: rate)))
        }

        return items
    }

    /// `splitAmounts` (custom, unequal shares) takes priority when present;
    /// otherwise divides `amount` evenly across `splitUIDs`. Custom amounts
    /// are entered in the item's own currency, so `rate` (1 when currencies
    /// already match) converts them the same way `amount` was converted.
    private static func shares(amount: Double, splitUIDs: [String], splitAmounts: [String: Double], rate: Double) -> [String: Double] {
        guard splitAmounts.isEmpty else {
            return splitUIDs.reduce(into: [:]) { result, uid in
                result[uid] = (splitAmounts[uid] ?? 0) * rate
            }
        }
        let evenShare = amount / Double(splitUIDs.count)
        return Dictionary(uniqueKeysWithValues: splitUIDs.map { ($0, evenShare) })
    }
}
