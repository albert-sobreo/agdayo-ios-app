import Foundation

/// One person's share of the trip's costs, by kind.
struct MemberCosts {
    var activities: Double = 0
    var stays: Double = 0
    var transport: Double = 0
    var expenses: Double = 0
    /// What they actually paid for (items with them as "Paid by").
    var paid: Double = 0

    var total: Double { activities + stays + transport + expenses }
}

/// The kinds of cost the Budget screen breaks down.
enum CostKind: String, CaseIterable, Identifiable {
    case activities, stays, transport, expenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activities: return "Activities"
        case .stays: return "Stays"
        case .transport: return "Transport"
        case .expenses: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .activities: return "map"
        case .stays: return "bed.double"
        case .transport: return "airplane"
        case .expenses: return "cart"
        }
    }
}

/// One costed item with each person's share of it.
struct CostContribution: Identifiable {
    let id: UUID
    let title: String
    /// In the trip's currency; nil when it's in another currency with no rate saved.
    let total: Double?
    let paidByUID: String?
    let shares: [String: Double]
}

/// Who chips in for what: each person's share of every activity, stay, ride and
/// expense. Unlike `ExpenseBalanceService` (which only counts items with a payer
/// and a split, to settle up), every costed item counts here: a split item by its
/// split, and an item with no split as a shared cost, evenly across everyone.
/// Pure functions over the caller's live arrays, like `ExpenseBalanceService`.
enum MemberCostService {
    static func itemShares(
        cost: Double,
        rate: Double,
        splitUIDs: [String],
        splitAmounts: [String: Double],
        memberUIDs: [String]
    ) -> [String: Double] {
        let members = Set(memberUIDs)
        if splitUIDs.isEmpty {
            guard !memberUIDs.isEmpty else { return [:] }
            return ExpenseBalanceService.shares(amount: cost, splitUIDs: memberUIDs, splitAmounts: [:], rate: 1, memberUIDs: members)
        }
        return ExpenseBalanceService.shares(amount: cost, splitUIDs: splitUIDs, splitAmounts: splitAmounts, rate: rate, memberUIDs: members)
    }

    static func contributions(
        _ kind: CostKind,
        activities: [Activity],
        accommodations: [Accommodation],
        transportSegments: [TransportSegment],
        expenses: [Expense],
        currency: String,
        memberUIDs: [String]
    ) -> [CostContribution] {
        func row(id: UUID, title: String, converted: (cost: Double, rate: Double)?, paidByUID: String?, splitUIDs: [String], splitAmounts: [String: Double]) -> CostContribution {
            let shares = converted.map {
                itemShares(cost: $0.cost, rate: $0.rate, splitUIDs: splitUIDs, splitAmounts: splitAmounts, memberUIDs: memberUIDs)
            } ?? [:]
            return CostContribution(id: id, title: title, total: converted?.cost, paidByUID: paidByUID, shares: shares)
        }

        switch kind {
        case .activities:
            return activities
                .filter { ($0.cost ?? 0) > 0 }
                .sorted { $0.date < $1.date }
                .map { row(id: $0.id, title: $0.title, converted: $0.costAndRate(inTripCurrency: currency), paidByUID: $0.paidByUID, splitUIDs: $0.splitUIDs, splitAmounts: $0.splitAmounts) }
        case .stays:
            return accommodations
                .filter { $0.totalCost > 0 }
                .sorted { $0.startDate < $1.startDate }
                .map { row(id: $0.id, title: $0.name, converted: ($0.totalCost, 1), paidByUID: $0.paidByUID, splitUIDs: $0.splitUIDs, splitAmounts: $0.splitAmounts) }
        case .transport:
            return transportSegments
                .filter { $0.cost > 0 }
                .sorted { $0.departureDate < $1.departureDate }
                .map { row(id: $0.id, title: "\($0.departureLocation) → \($0.arrivalLocation)", converted: $0.costAndRate(inTripCurrency: currency), paidByUID: $0.paidByUID, splitUIDs: $0.splitUIDs, splitAmounts: $0.splitAmounts) }
        case .expenses:
            return expenses
                .filter { $0.cost > 0 }
                .sorted { ($0.dateTime ?? .distantPast) < ($1.dateTime ?? .distantPast) }
                .map { row(id: $0.id, title: $0.name, converted: $0.costAndRate(inTripCurrency: currency), paidByUID: $0.paidByUID, splitUIDs: $0.splitUIDs, splitAmounts: $0.splitAmounts) }
        }
    }

    /// Everyone's share by kind, plus what each paid.
    static func breakdown(
        activities: [Activity],
        accommodations: [Accommodation],
        transportSegments: [TransportSegment],
        expenses: [Expense],
        currency: String,
        memberUIDs: [String]
    ) -> [String: MemberCosts] {
        var result = Dictionary(uniqueKeysWithValues: memberUIDs.map { ($0, MemberCosts()) })
        for kind in CostKind.allCases {
            let rows = contributions(kind, activities: activities, accommodations: accommodations, transportSegments: transportSegments, expenses: expenses, currency: currency, memberUIDs: memberUIDs)
            for row in rows {
                for (uid, share) in row.shares where result[uid] != nil {
                    switch kind {
                    case .activities: result[uid]?.activities += share
                    case .stays: result[uid]?.stays += share
                    case .transport: result[uid]?.transport += share
                    case .expenses: result[uid]?.expenses += share
                    }
                }
                if let payer = row.paidByUID, let total = row.total, result[payer] != nil {
                    result[payer]?.paid += total
                }
            }
        }
        return result
    }
}
