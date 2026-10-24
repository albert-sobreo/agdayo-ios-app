import Foundation

struct TripPollDTO: Codable {
    var kind: String
    var question: String
    var options: [String]
    /// Optional so a poll nobody has voted on yet decodes cleanly.
    var votes: [String: Int]?
    var createdByUID: String
    var createdAt: Date
    var isClosed: Bool
    var location: String?
    var latitude: Double?
    var longitude: Double?
    var iconName: String?
    var proposedDate: Date?
}

extension TripPoll {
    var dto: TripPollDTO {
        TripPollDTO(
            kind: kind.rawValue, question: question, options: options, votes: votes,
            createdByUID: createdByUID, createdAt: createdAt, isClosed: isClosed,
            location: location, latitude: latitude, longitude: longitude,
            iconName: iconName, proposedDate: proposedDate
        )
    }

    convenience init(id: UUID, dto: TripPollDTO, trip: Trip) {
        self.init(
            id: id, kind: PollKind(rawValue: dto.kind) ?? .question, question: dto.question,
            options: dto.options, votes: dto.votes ?? [:], createdByUID: dto.createdByUID,
            createdAt: dto.createdAt, isClosed: dto.isClosed, location: dto.location ?? "",
            latitude: dto.latitude, longitude: dto.longitude,
            iconName: dto.iconName ?? "mappin.and.ellipse", proposedDate: dto.proposedDate, trip: trip
        )
    }

    func apply(_ dto: TripPollDTO) {
        kind = PollKind(rawValue: dto.kind) ?? kind
        question = dto.question
        options = dto.options
        votes = dto.votes ?? [:]
        createdByUID = dto.createdByUID
        createdAt = dto.createdAt
        isClosed = dto.isClosed
        location = dto.location ?? ""
        latitude = dto.latitude
        longitude = dto.longitude
        iconName = dto.iconName ?? iconName
        proposedDate = dto.proposedDate
    }
}
