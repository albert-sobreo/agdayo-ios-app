import Foundation
import SwiftData

enum VacationType: String, Codable, CaseIterable, Identifiable {
    case beaches, mountains, parks, cities, province, other

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var fullName: String
    var homeRegion: String
    var hasTravelExperience: Bool
    var preferredVacationTypes: [VacationType]

    init(
        id: UUID = UUID(),
        fullName: String = "",
        homeRegion: String = "",
        hasTravelExperience: Bool = false,
        preferredVacationTypes: [VacationType] = []
    ) {
        self.id = id
        self.fullName = fullName
        self.homeRegion = homeRegion
        self.hasTravelExperience = hasTravelExperience
        self.preferredVacationTypes = preferredVacationTypes
    }
}
