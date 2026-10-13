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
struct SuggestionOption {

    @Guide(description: "Activity or place name.")
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

/// A single labeled group of alternative suggestions — e.g. "Lunch Spots"
/// (one group, several options) or "Day 1 — Morning" (one of several
/// groups making up a multi-day plan). `date`/`time` are always filled in,
/// even for a one-off ask with no explicit day/time in the prompt, so
/// `AIItineraryReviewSheet.commit()` has one code path regardless of which
/// kind of request produced the group.
@available(iOS 26.0, *)
@Generable
struct SuggestionGroup {

    @Guide(description: "Short label for this group, e.g. 'Lunch Spots' or 'Day 1 — Morning'.")
    var label: String

    @Guide(description: "ISO date (yyyy-MM-dd), within the trip dates. Pick a sensible day even if the request didn't name one.")
    var date: String

    @Guide(description: "24-hour time (HH:mm). Pick a sensible time for the activity/meal type even if the request didn't name one.")
    var time: String

    @Guide(
        description: "2 to 5 distinct options for this group.",
        .count(2...5)
    )
    var options: [SuggestionOption]
}

/// Root response shape for every AI ask in `AIItineraryReviewSheet` — a flat
/// list of groups. There's no "kind" field: a one-off category ask
/// naturally comes back as a single group, a multi-day plan as several, and
/// the UI/commit logic only ever branches on that structural shape, not on
/// the model's self-report.
@available(iOS 26.0, *)
@Generable
struct AISuggestionResponse {

    @Guide(description: "One or more groups of suggestions answering the request.")
    var groups: [SuggestionGroup]
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
            return "Couldn't generate suggestions for that request. Try rephrasing it."

        case .noPlacesFound:
            return "Couldn't find nearby places for this destination."

        case .other(let error):
            return "Couldn't generate suggestions: \(error.localizedDescription)"
        }
    }
}

@available(iOS 26.0, *)
enum AISuggestionService {

    /// - Parameters:
    ///   - places: Grounding place candidates — fetched once per sheet
    ///     session by the caller (`TripPlaceDiscovery.search`), not
    ///     per-turn, since they're a pure function of trip location.
    ///   - priorSuggestionsSummary: Every option already suggested earlier
    ///     this session (selected or not), so a later ask like "another
    ///     lunch option" doesn't repeat itself or collide on time slot.
    ///   - anchor: The coordinate to rank proximity from — the previous
    ///     turn's top pick when there is one, otherwise the trip's center.
    static func generate(
        for trip: Trip,
        prompt: String,
        places: [TripPlaceDiscovery.PlaceCandidate],
        priorSuggestionsSummary: String,
        anchor: CLLocationCoordinate2D?
    ) async throws -> [SuggestionGroup] {

        guard !places.isEmpty else {
            throw ItineraryGenerationError.noPlacesFound
        }

        let placeList = places
            .map { place in
                let locality = place.locality.map { " (\($0))" } ?? ""
                return "- \(place.name) [\(place.category)]\(locality)"
            }
            .joined(separator: "\n")

        // Deliberately NOT `.iso8601` here — that FormatStyle defaults to
        // GMT, while `trip.startDate`/`endDate` are anchored to the
        // device's local calendar day (see `Trip.status`'s use of
        // `calendar.startOfDay`). Formatting in GMT shifted the date shown
        // to the model back by a day for anyone east of UTC.
        let tripStart = isoDateString(from: trip.startDate)
        let tripEnd = isoDateString(from: trip.endDate)

        let existingActivities = itinerarySummary(for: trip)

        let session = LanguageModelSession {
            """
            Answer travel-planning requests for a trip in \(trip.location)
            with real, selectable suggestions — never with plain text.

            TRIP DATES
            Start: \(tripStart)
            End: \(tripEnd)

            Every group's date MUST be within the trip dates.

            RESPONSE SHAPE
            If the request is about one meal, activity, or category (e.g.
            "lunch suggestions", "something to do near the hotel"), return
            exactly ONE group with 2 to 5 distinct options for that single
            ask.
            If the request is for a multi-day plan or full itinerary,
            return one group per time-of-day block per day (e.g.
            breakfast/lunch/dinner or morning/afternoon/evening), covering
            the number of days asked for (or the whole trip if unspecified),
            keeping groups in chronological order.

            EXISTING ITINERARY
            \(existingActivities)

            Use the existing itinerary to understand what has already
            been planned. Do not duplicate existing activities. Prefer
            different places and experiences from activities already in
            the itinerary.

            ALREADY SUGGESTED THIS SESSION
            \(priorSuggestionsSummary)

            Do not repeat any of the above, and do not reuse the same date
            and time already used above.

            REAL PLACES
            Each line below is: place name [category] (neighborhood, if
            known). Use ONLY the real places listed below. Never invent a
            place, and never modify a listed name (no adding/removing
            words, no translating it, no guessing a different branch or
            location). The location field must be copied exactly as the
            place name only — never include the bracketed category or the
            neighborhood in the location field.
            Match the request to the right category: a meal/food ask must
            only use [Restaurant] or [Cafe] places; a museum/history ask
            must only use [Museum] or [Attraction] places; outdoor/nature
            asks must only use [Park] places. If nothing below fits the
            request well, say so plainly in a short title/description
            rather than inventing a place that isn't listed.

            \(placeList)

            GENERAL RULES
            Use local currency.
            Keep descriptions short and factual — one sentence, based only
            on the place's name and category above. Do not invent specific
            menu items, prices, opening hours, or awards/reputation claims
            you can't know from the name and category alone.
            Always fill in a specific date and time for every group, even
            for a single-category ask with no day/time named in the
            request — pick whichever is most realistic (e.g. lunch around
            midday, dinner in the evening).
            """
        }

        do {
            let response = try await session.respond(
                to: prompt,
                generating: AISuggestionResponse.self
            )

            var groups = await ItineraryDistanceRanking.rank(
                response.content.groups,
                around: anchor
            )

            // A multi-day plan (more than one group) keeps only the
            // closest-ranked pair per group, matching the "recommended +
            // one alternative" pattern the review UI expects for a day
            // plan. A lone ad-hoc group keeps every option offered.
            if groups.count > 1 {
                groups = groups.map { group in
                    var clamped = group
                    clamped.options = Array(group.options.prefix(2))
                    return clamped
                }
            }

            return groups

        } catch let error as LanguageModelSession.GenerationError {

            print("[AI suggestions] generation error: \(error)")

            switch error {
            case .exceededContextWindowSize:
                throw ItineraryGenerationError.contextWindowExceeded

            case .guardrailViolation:
                throw ItineraryGenerationError.guardrailViolation

            default:
                throw ItineraryGenerationError.other(error)
            }

        } catch {

            print("[AI suggestions] generation error: \(error)")

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

                let date = isoDateString(from: activity.date)

                let location = activity.location.isEmpty
                    ? ""
                    : " — \(activity.location)"

                return "- \(date): \(activity.title)\(location)"
            }
            .joined(separator: "\n")
    }

    /// "yyyy-MM-dd" in the device's current calendar/time zone — matches
    /// how `AIItineraryReviewSheet` parses the model's returned dates back
    /// (also local, not UTC), so a date round-trips to the same day.
    private static func isoDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
