import Foundation

/// One costed thing on a day, in the trip's currency.
struct BudgetLineItem: Identifiable {
    enum Kind {
        case activity, stay, transport, expense

        var label: String {
            switch self {
            case .activity: return "Activity"
            case .stay: return "Stay"
            case .transport: return "Transport"
            case .expense: return "Expense"
            }
        }
    }

    let id: String
    let sourceID: UUID
    let kind: Kind
    let title: String
    /// e.g. "Night 2 of 3" for a stay spread over several nights.
    let subtitle: String?
    let iconName: String
    let amount: Double
    let categoryID: UUID?
    let memberUID: String?
}

struct DayBudget: Identifiable {
    let day: Date
    let items: [BudgetLineItem]
    /// A day that hasn't happened yet, so its figures are plans rather than spending.
    let isPlanned: Bool

    var id: Date { day }
    var total: Double { items.reduce(0) { $0 + $1.amount } }
}

/// A group of one day's items under the same budget category.
struct CategorySlice: Identifiable {
    static let uncategorizedName = "Uncategorized"
    static let memberBudgetsName = "Member budgets"

    let name: String
    let items: [BudgetLineItem]

    var id: String { name }
    var amount: Double { items.reduce(0) { $0 + $1.amount } }
}

struct BudgetReport {
    var days: [DayBudget]
    /// Expenses entered without a date — counted in the budget, but not on any day.
    var undated: [BudgetLineItem]
    /// Costed items left out because they're in another currency with no exchange
    /// rate captured yet, exactly as the Budget screen's totals leave them out.
    var skippedWithoutRate: Int
    /// The overall budget spread evenly over the trip's days, if there's a budget.
    var dailyAllowance: Double?
}

/// Works out what was (or is planned to be) spent each day. Pure calculation,
/// so the numbers match the Budget screen: the same exchange-rate conversion,
/// and everything a day-by-day view can place on a day adds up to the same total.
enum DailyBudgetService {
    static func report(
        trip: Trip,
        activities: [Activity],
        accommodations: [Accommodation],
        transportSegments: [TransportSegment],
        expenses: [Expense],
        now: Date = .now
    ) -> BudgetReport {
        let calendar = Calendar.current
        var byDay: [Date: [BudgetLineItem]] = [:]
        var undated: [BudgetLineItem] = []
        var skipped = 0

        for activity in activities {
            guard let cost = activity.cost, cost > 0 else { continue }
            guard let converted = activity.costAndRate(inTripCurrency: trip.currency)?.cost else {
                skipped += 1
                continue
            }
            byDay[calendar.startOfDay(for: activity.date), default: []].append(BudgetLineItem(
                id: "activity-\(activity.id)", sourceID: activity.id, kind: .activity,
                title: activity.title, subtitle: nil, iconName: activity.iconName, amount: converted,
                categoryID: activity.budgetCategoryID, memberUID: activity.budgetMemberUID
            ))
        }

        for segment in transportSegments where segment.cost > 0 {
            guard let converted = segment.costAndRate(inTripCurrency: trip.currency)?.cost else {
                skipped += 1
                continue
            }
            let route = segment.arrivalLocation.isEmpty ? "" : " to \(segment.arrivalLocation)"
            byDay[calendar.startOfDay(for: segment.departureDate), default: []].append(BudgetLineItem(
                id: "transport-\(segment.id)", sourceID: segment.id, kind: .transport,
                title: segment.mode.displayName + route, subtitle: nil, iconName: segment.mode.iconName, amount: converted,
                categoryID: segment.budgetCategoryID, memberUID: segment.budgetMemberUID
            ))
        }

        // A stay is one cost for several nights; spread it evenly across them.
        for stay in accommodations where stay.totalCost > 0 {
            let first = calendar.startOfDay(for: stay.startDate)
            let last = calendar.startOfDay(for: stay.endDate)
            let nights = max(1, calendar.dateComponents([.day], from: first, to: last).day ?? 1)
            let perNight = stay.totalCost / Double(nights)
            for night in 0..<nights {
                guard let day = calendar.date(byAdding: .day, value: night, to: first) else { continue }
                byDay[day, default: []].append(BudgetLineItem(
                    id: "stay-\(stay.id)-\(night)", sourceID: stay.id, kind: .stay,
                    title: stay.name, subtitle: nights > 1 ? "Night \(night + 1) of \(nights)" : nil,
                    iconName: "bed.double", amount: perNight,
                    categoryID: stay.budgetCategoryID, memberUID: stay.budgetMemberUID
                ))
            }
        }

        for expense in expenses where expense.cost > 0 {
            guard let converted = expense.costAndRate(inTripCurrency: trip.currency)?.cost else {
                skipped += 1
                continue
            }
            let item = BudgetLineItem(
                id: "expense-\(expense.id)", sourceID: expense.id, kind: .expense,
                title: expense.name, subtitle: nil, iconName: "cart", amount: converted,
                categoryID: expense.budgetCategoryID, memberUID: expense.budgetMemberUID
            )
            if let date = expense.date {
                byDay[calendar.startOfDay(for: date), default: []].append(item)
            } else {
                undated.append(item)
            }
        }

        // Every trip day, plus any other day something was booked on.
        let tripDays = trip.calendarDays
        let today = calendar.startOfDay(for: now)
        let days = Set(tripDays).union(byDay.keys).sorted().map { day in
            DayBudget(day: day, items: byDay[day] ?? [], isPlanned: day > today)
        }

        let allowance: Double? = trip.overallBudget > 0 && !tripDays.isEmpty
            ? trip.overallBudget / Double(tripDays.count)
            : nil

        return BudgetReport(days: days, undated: undated, skippedWithoutRate: skipped, dailyAllowance: allowance)
    }

    /// Groups items by budget category (or member budget, or none), biggest first.
    static func slices(for items: [BudgetLineItem], categories: [BudgetCategory]) -> [CategorySlice] {
        let names = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let grouped = Dictionary(grouping: items) { item -> String in
            if let categoryID = item.categoryID, let name = names[categoryID] { return name }
            if item.memberUID != nil { return CategorySlice.memberBudgetsName }
            return CategorySlice.uncategorizedName
        }
        return grouped
            .map { CategorySlice(name: $0.key, items: $0.value.sorted { $0.amount > $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }
}
