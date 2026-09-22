import FoundationModels

@Generable(description: "A suggested day-by-day itinerary for a trip")
struct GeneratedItinerary {
    @Guide(.minimumCount(3))
    var activities: [GeneratedActivity]
}

/// Deliberately has no latitude/longitude field — only a text search query.
/// The on-device model can't ground suggestions in real places the way the
/// web app's Gemini+Google-Places tool-calling did, so every suggestion must
/// be resolved through a real MapKit search before it can carry a coordinate.
@Generable(description: "A single suggested activity in an itinerary")
struct GeneratedActivity {
    @Guide(description: "Short, specific activity title. No dates or times.")
    var title: String

    @Guide(description: "One or two sentence description of the activity.")
    var activityDescription: String

    @Guide(description: "A short search phrase suitable for a maps search, e.g. 'Rizal Park Manila' — a real, verifiable place, never a coordinate.")
    var suggestedLocationQuery: String

    @Guide(description: "0-based day offset from the trip's start date.")
    var dayOffset: Int

    @Guide(description: "Approximate time of day in 24-hour HH:mm format, e.g. '09:00'.")
    var approximateTime: String

    @Guide(description: "Estimated cost in the trip's currency. 0 if free.")
    var estimatedCost: Double

    @Guide(description: "An SF Symbols name that fits the activity, e.g. 'fork.knife', 'camera', 'bus'.")
    var iconName: String
}
