import Foundation

struct ExpenseDTO: Codable {
    var name: String
    var date: Date?
    var time: String?
    var cost: Double
    var costCurrency: String?
    var exchangeRateToTripCurrency: Double?
    var budgetCategoryID: UUID?
    var budgetMemberUID: String?
    var paidByUID: String?
    var splitUIDs: [String]?
    var splitAmounts: [String: Double]?
}

extension Expense {
    var dto: ExpenseDTO {
        ExpenseDTO(
            name: name,
            date: date,
            time: time,
            cost: cost,
            costCurrency: costCurrency,
            exchangeRateToTripCurrency: exchangeRateToTripCurrency,
            budgetCategoryID: budgetCategoryID,
            budgetMemberUID: budgetMemberUID,
            paidByUID: paidByUID,
            splitUIDs: splitUIDs,
            splitAmounts: splitAmounts.isEmpty ? nil : splitAmounts
        )
    }

    convenience init(id: UUID, dto: ExpenseDTO, trip: Trip) {
        self.init(
            id: id,
            name: dto.name,
            date: dto.date,
            time: dto.time,
            cost: dto.cost,
            costCurrency: dto.costCurrency,
            exchangeRateToTripCurrency: dto.exchangeRateToTripCurrency,
            budgetCategoryID: dto.budgetCategoryID,
            budgetMemberUID: dto.budgetMemberUID,
            paidByUID: dto.paidByUID,
            splitUIDs: dto.splitUIDs ?? [],
            splitAmounts: dto.splitAmounts ?? [:],
            trip: trip
        )
    }

    func apply(_ dto: ExpenseDTO) {
        name = dto.name
        date = dto.date
        time = dto.time
        cost = dto.cost
        costCurrency = dto.costCurrency
        exchangeRateToTripCurrency = dto.exchangeRateToTripCurrency
        budgetCategoryID = dto.budgetCategoryID
        budgetMemberUID = dto.budgetMemberUID
        paidByUID = dto.paidByUID
        splitUIDs = dto.splitUIDs ?? []
        splitAmounts = dto.splitAmounts ?? [:]
    }
}
