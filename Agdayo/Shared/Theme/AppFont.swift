import SwiftUI

/// Outfit (primary UI typeface) and Matatas One (decorative display face,
/// reserved for hero trip/place names) — matching the web app's `.outfit`
/// body-wide font and its `.baybayin` (Matatas One) hero treatment.
/// Both scale with Dynamic Type via `relativeTo:`.
enum AppFont {
    static func outfit(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(postscriptName(for: weight), size: size, relativeTo: style)
    }

    /// The web app's decorative hero typeface — use sparingly, for trip/place names only.
    static func matatasOne(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("MatatasOne-Bold", size: size, relativeTo: style)
    }

    private static func postscriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .black, .heavy: return "Outfit-Black"
        case .bold: return "Outfit-Bold"
        case .semibold: return "Outfit-SemiBold"
        case .medium: return "Outfit-Medium"
        default: return "Outfit-Regular"
        }
    }
}
