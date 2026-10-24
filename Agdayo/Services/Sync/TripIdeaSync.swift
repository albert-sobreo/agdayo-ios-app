import Foundation

struct TripIdeaDTO: Codable {
    var title: String
    var note: String?
    var location: String?
    var latitude: Double?
    var longitude: Double?
    var link: String?
    var addedByUID: String
    var createdAt: Date
    /// Optional so an idea nobody has liked yet decodes cleanly.
    var likedBy: [String]?
    var isPlanned: Bool?
}

extension TripIdea {
    var dto: TripIdeaDTO {
        TripIdeaDTO(
            title: title, note: note, location: location, latitude: latitude, longitude: longitude,
            link: link, addedByUID: addedByUID, createdAt: createdAt, likedBy: likedBy, isPlanned: isPlanned
        )
    }

    convenience init(id: UUID, dto: TripIdeaDTO, trip: Trip) {
        self.init(
            id: id, title: dto.title, note: dto.note ?? "", location: dto.location ?? "",
            latitude: dto.latitude, longitude: dto.longitude, link: dto.link ?? "",
            addedByUID: dto.addedByUID, createdAt: dto.createdAt, likedBy: dto.likedBy ?? [],
            isPlanned: dto.isPlanned ?? false, trip: trip
        )
    }

    func apply(_ dto: TripIdeaDTO) {
        title = dto.title
        note = dto.note ?? ""
        location = dto.location ?? ""
        latitude = dto.latitude
        longitude = dto.longitude
        link = dto.link ?? ""
        addedByUID = dto.addedByUID
        createdAt = dto.createdAt
        likedBy = dto.likedBy ?? []
        isPlanned = dto.isPlanned ?? false
    }
}
