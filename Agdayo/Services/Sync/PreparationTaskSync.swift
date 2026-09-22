import Foundation

struct PreparationTaskDTO: Codable {
    var name: String
    var category: String
    var notes: String
    var completed: Bool
}

extension PreparationTask {
    var dto: PreparationTaskDTO {
        PreparationTaskDTO(name: name, category: category, notes: notes, completed: completed)
    }

    convenience init(id: UUID, dto: PreparationTaskDTO, trip: Trip) {
        self.init(id: id, name: dto.name, category: dto.category, notes: dto.notes, completed: dto.completed, trip: trip)
    }

    func apply(_ dto: PreparationTaskDTO) {
        name = dto.name
        category = dto.category
        notes = dto.notes
        completed = dto.completed
    }
}
