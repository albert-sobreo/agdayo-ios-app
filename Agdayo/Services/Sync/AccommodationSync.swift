import Foundation

struct AccommodationDTO: Codable {
    var name: String
    var type: AccommodationType
    var location: String
    var numberOfRooms: Int
    var totalCost: Double
    var checkInTime: String
    var checkOutTime: String
    var startDate: Date
    var endDate: Date
}

extension Accommodation {
    var dto: AccommodationDTO {
        AccommodationDTO(
            name: name,
            type: type,
            location: location,
            numberOfRooms: numberOfRooms,
            totalCost: totalCost,
            checkInTime: checkInTime,
            checkOutTime: checkOutTime,
            startDate: startDate,
            endDate: endDate
        )
    }

    convenience init(id: UUID, dto: AccommodationDTO, trip: Trip) {
        self.init(
            id: id,
            name: dto.name,
            type: dto.type,
            location: dto.location,
            numberOfRooms: dto.numberOfRooms,
            totalCost: dto.totalCost,
            checkInTime: dto.checkInTime,
            checkOutTime: dto.checkOutTime,
            startDate: dto.startDate,
            endDate: dto.endDate,
            trip: trip
        )
    }

    func apply(_ dto: AccommodationDTO) {
        name = dto.name
        type = dto.type
        location = dto.location
        numberOfRooms = dto.numberOfRooms
        totalCost = dto.totalCost
        checkInTime = dto.checkInTime
        checkOutTime = dto.checkOutTime
        startDate = dto.startDate
        endDate = dto.endDate
    }
}
