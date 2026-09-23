import Foundation

struct SettlementDTO: Codable {
    var fromUID: String
    var toUID: String
    var amount: Double
    var date: Date
}

extension Settlement {
    var dto: SettlementDTO {
        SettlementDTO(fromUID: fromUID, toUID: toUID, amount: amount, date: date)
    }

    convenience init(id: UUID, dto: SettlementDTO, trip: Trip) {
        self.init(
            id: id,
            fromUID: dto.fromUID,
            toUID: dto.toUID,
            amount: dto.amount,
            date: dto.date,
            trip: trip
        )
    }

    func apply(_ dto: SettlementDTO) {
        fromUID = dto.fromUID
        toUID = dto.toUID
        amount = dto.amount
        date = dto.date
    }
}
