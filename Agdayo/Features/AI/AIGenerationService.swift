import FoundationModels
import Foundation

/// Plain Swift service — no SwiftUI import — so it stays testable and
/// separate from the availability-gating and review UI.
struct AIGenerationService {
    func generateItinerary(
        tripName: String,
        location: String,
        startDate: Date,
        endDate: Date,
        budget: Double,
        currency: String,
        additionalDetails: String,
        profile: UserProfile?
    ) async throws -> GeneratedItinerary {
        let dayCount = max(1, (Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0) + 1)

        let session = LanguageModelSession(
            instructions: """
            You are a travel planning assistant. Suggest a realistic, day-by-day
            itinerary made only of real, verifiable places. Never invent coordinates —
            you only provide a short search phrase for each location.
            """
        )

        var contextLines = [
            "Trip name: \(tripName)",
            "Destination: \(location)",
            "Duration: \(dayCount) day(s), day offsets 0 through \(dayCount - 1)",
            "Budget: \(budget) \(currency)",
        ]
        if let profile, profile.hasTravelExperience {
            contextLines.append("The traveler has prior travel experience.")
        }
        if let profile, !profile.preferredVacationTypes.isEmpty {
            let types = profile.preferredVacationTypes.map(\.displayName).joined(separator: ", ")
            contextLines.append("Preferred vacation types: \(types).")
        }
        if !additionalDetails.trimmingCharacters(in: .whitespaces).isEmpty {
            contextLines.append("Additional request: \(additionalDetails)")
        }

        let prompt = contextLines.joined(separator: "\n")
        let response = try await session.respond(to: prompt, generating: GeneratedItinerary.self)
        return response.content
    }
}
