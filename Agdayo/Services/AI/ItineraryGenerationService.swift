import CoreLocation
import Foundation
import FoundationModels

enum AIAvailability {

    static var isItineraryGenerationAvailable: Bool {
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }

        return false
    }
}

@available(iOS 26.0, *)
@Generable
struct GeneratedActivity {

    @Guide(description: "Activity name.")
    var title: String

    @Guide(description: "Real place and city.")
    var location: String

    @Guide(description: "Short description.")
    var description: String

    @Guide(description: "SF Symbol name.")
    var iconName: String

    @Guide(description: "Estimated cost.", .range(0...1_000_000))
    var cost: Double

    @Guide(description: "ISO currency code.")
    var costCurrency: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedTimeBlock {

    @Guide(description: "Block name.")
    var label: String

    @Guide(description: "24-hour time.")
    var time: String

    @Guide(
        description: "Two different options.",
        .count(2...2)
    )
    var options: [GeneratedActivity]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedDay {

    @Guide(description: "ISO date.")
    var date: String

    @Guide(
        description: "Chronological itinerary.",
        .count(3...3)
    )
    var timeBlocks: [GeneratedTimeBlock]
}

@available(iOS 26.0, *)
enum ItineraryGenerationError: LocalizedError {

    case contextWindowExceeded
    case guardrailViolation
    case noPlacesFound
    case other(Error)

    var errorDescription: String? {
        switch self {
        case .contextWindowExceeded:
            return "That request was too long. Try a shorter or simpler prompt."

        case .guardrailViolation:
            return "Couldn't generate an itinerary for that request. Try rephrasing it."

        case .noPlacesFound:
            return "Couldn't find nearby places for this destination."

        case .other(let error):
            return "Couldn't generate an itinerary: \(error.localizedDescription)"
        }
    }
}

@available(iOS 26.0, *)
enum ItineraryGenerationService {

    static func generate(
        for trip: Trip,
        prompt: String
    ) async throws -> [GeneratedDay] {

        let center = trip.coordinate
            ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)

        let places = await TripPlaceDiscovery.search(
            near: center,
            destination: trip.location
        )

        guard !places.isEmpty else {
            throw ItineraryGenerationError.noPlacesFound
        }

        let placeList = places
            .map {
                "- \($0.name) [\($0.category)]"
            }
            .joined(separator: "\n")

        let tripStart = trip.startDate.formatted(
            .iso8601
                .year()
                .month()
                .day()
        )

        let tripEnd = trip.endDate.formatted(
            .iso8601
                .year()
                .month()
                .day()
        )

        let existingActivities = itinerarySummary(for: trip)

        let session = LanguageModelSession {
            """
            Plan a realistic itinerary in \(trip.location).

            TRIP DATES
            Start: \(tripStart)
            End: \(tripEnd)

            The generated date MUST be within the trip dates.
            Never generate an activity outside the trip dates.

            EXISTING ITINERARY
            \(existingActivities)

            Use the existing itinerary to understand what has already
            been planned.

            Do not duplicate existing activities.
            Prefer different places and experiences from activities
            already in the itinerary.

            REAL PLACES
            Use ONLY the real places listed below.
            Never invent or modify a place name.
            The location field must use the exact place name from this list.

            \(placeList)

            GENERAL RULES
            Use local currency.
            Keep activities chronological.
            Provide two different options for each time block.
            """
        }

        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedDay.self
            )

            let anchor = lastPlannedCoordinate(for: trip)
                ?? trip.coordinate

            return await ItineraryDistanceRanking.rank(
                [response.content],
                around: anchor
            )

        } catch let error as LanguageModelSession.GenerationError {

            print("[AI itinerary] generation error: \(error)")

            switch error {
            case .exceededContextWindowSize:
                throw ItineraryGenerationError.contextWindowExceeded

            case .guardrailViolation:
                throw ItineraryGenerationError.guardrailViolation

            default:
                throw ItineraryGenerationError.other(error)
            }

        } catch {

            print("[AI itinerary] generation error: \(error)")

            throw ItineraryGenerationError.other(error)
        }
    }

    private static func itinerarySummary(for trip: Trip) -> String {

        let activities = trip.activities
            .sorted { $0.date < $1.date }

        guard !activities.isEmpty else {
            return "No activities have been planned yet."
        }

        return activities
            .map { activity in

                let date = activity.date.formatted(
                    .iso8601
                        .year()
                        .month()
                        .day()
                )

                let location = activity.location.isEmpty
                    ? ""
                    : " — \(activity.location)"

                return "- \(date): \(activity.title)\(location)"
            }
            .joined(separator: "\n")
    }

    private static func lastPlannedCoordinate(
        for trip: Trip
    ) -> CLLocationCoordinate2D? {

        trip.activities
            .sorted { $0.date < $1.date }
            .last(where: { $0.coordinate != nil })?
            .coordinate
    }
}
