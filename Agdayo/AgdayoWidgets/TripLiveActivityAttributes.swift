import ActivityKit
import Foundation

/// Kept in sync by hand with the identical copy in the main `Agdayo` app
/// target (`Agdayo/Services/LiveActivity/TripLiveActivityAttributes.swift`)
/// — there's no shared framework target, and this extension can't depend
/// on the main app's SwiftData/Firebase-laden module, so this tiny,
/// dependency-free file is just duplicated into both targets instead.
/// Deliberately plain `Codable` data only (no `TripTheme`/`Color` types)
/// so it compiles in this extension process unchanged.
struct TripLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// "Day 2", shown as a small label alongside the trip name.
        var dayLabel: String
        var currentActivityName: String?
        var currentActivityLocation: String?
        var nextActivityName: String?
        var nextActivityLocation: String?
        var nextActivityStartDate: Date?
    }

    var tripID: String
    var tripName: String
    /// Plain hex string (e.g. "F0A693") — this extension has no access to
    /// `TripTheme.accentColor`, so the color is resolved to a hex value
    /// once in the main app before starting the activity.
    var themeColorHex: String
}
