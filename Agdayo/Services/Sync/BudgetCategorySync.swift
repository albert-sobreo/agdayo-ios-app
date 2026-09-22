import Foundation

struct BudgetCategoryDTO: Codable {
    var name: String
    var amount: Double
}

extension BudgetCategory {
    var dto: BudgetCategoryDTO {
        BudgetCategoryDTO(name: name, amount: amount)
    }

    convenience init(id: UUID, dto: BudgetCategoryDTO, trip: Trip) {
        self.init(id: id, name: dto.name, amount: dto.amount, trip: trip)
    }

    func apply(_ dto: BudgetCategoryDTO) {
        name = dto.name
        amount = dto.amount
    }
}
