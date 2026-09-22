import SwiftUI

/// Colors reverse-engineered from the web app's Tailwind theme tokens
/// (peach/sky/amber/emerald 50/200/500 shades, plus its light border/shadow tints).
extension TripTheme {
    /// The "500" brand shade — primary accent, progress fill, icon tint.
    var accentColor: Color {
        switch self {
        case .peach: return Color(hex: 0xF0A693)
        case .blue: return Color(hex: 0x0EA5E9)
        case .amber: return Color(hex: 0xF59E0B)
        case .emerald: return Color(hex: 0x10B981)
        }
    }

    /// The "50" shade — themed header block background.
    var headerBackground: Color {
        switch self {
        case .peach: return Color(hex: 0xFFF6F3)
        case .blue: return Color(hex: 0xF0F9FF)
        case .amber: return Color(hex: 0xFFFBEB)
        case .emerald: return Color(hex: 0xECFDF5)
        }
    }

    /// The "200" shade — unfilled progress track / secondary tint.
    var trackColor: Color {
        switch self {
        case .peach: return Color(hex: 0xFDD3C7)
        case .blue: return Color(hex: 0xBAE6FD)
        case .amber: return Color(hex: 0xFDE68A)
        case .emerald: return Color(hex: 0xA7F3D0)
        }
    }

    /// The "100" shade — light pill background (date/location tags).
    var lightTintColor: Color {
        switch self {
        case .peach: return Color(hex: 0xFFEAE5)
        case .blue: return Color(hex: 0xE0F2FE)
        case .amber: return Color(hex: 0xFEF3C7)
        case .emerald: return Color(hex: 0xD1FAE5)
        }
    }

    /// Card border + hard "sticker" shadow tint.
    var borderTint: Color {
        switch self {
        case .peach: return Color(hex: 0xF1E3E0)
        case .blue: return Color(hex: 0xE0F2FE)
        case .amber: return Color(hex: 0xFEF3C7)
        case .emerald: return Color(hex: 0xE6FAF2)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Peach 500 — the app's primary brand accent, used for the global tint.
    static let appPrimary = Color(hex: 0xF0A693)
    /// Zinc-ish neutral used for secondary surfaces/borders, matching the web app's `zinc` scale.
    static let appSecondary = Color(hex: 0xD4D4D8)
    static let appDanger = Color(hex: 0xE11D48)
    static let appSuccess = Color(hex: 0x10B981)
    static let appInfo = Color(hex: 0x0EA5E9)
    static let appWarning = Color(hex: 0xF59E0B)
}
