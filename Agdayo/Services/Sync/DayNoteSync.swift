import Foundation

struct DayNoteDTO: Codable {
    var day: Date
    var title: String
    var content: String
}

extension DayNote {
    var dto: DayNoteDTO {
        DayNoteDTO(day: day, title: title, content: content)
    }

    convenience init(id: UUID, dto: DayNoteDTO, trip: Trip) {
        self.init(id: id, day: dto.day, title: dto.title, content: dto.content, trip: trip)
    }

    func apply(_ dto: DayNoteDTO) {
        day = dto.day
        title = dto.title
        content = dto.content
    }
}
