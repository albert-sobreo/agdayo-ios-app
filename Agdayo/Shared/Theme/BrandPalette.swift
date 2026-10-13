import SwiftUI

/// The fixed, theme-agnostic palette introduced by the Home/Trip Detail
/// redesign mockups — maroon headlines on a blush-pink hero surface, mint
/// status accent, off-white canvas. Unlike `TripTheme`'s 8 selectable accent
/// colors, this palette doesn't vary per trip; it's the app's new brand
/// identity layered on top. Hex values are eyeballed from the mockups and
/// may need fine-tuning once compared side-by-side on device.
enum BrandPalette {
    /// Off-white page background outside the hero surface.
    static let canvas = Color(hex: 0xF3F0EC)
    /// Dusty-pink wash behind the active-trip hero card / trip detail header.
    static let blush = Color(hex: 0xFBDED9)
    /// Deep maroon — hero headlines ("TOKYO"), "View on Map", category icons.
    static let maroon = Color(hex: 0x8A2A35)
    /// Brighter rose-red — progress fill, the "D" member avatar.
    static let rose = Color(hex: 0xD9444E)
    /// Unfilled progress track, a lighter tint of `rose`.
    static let roseTrack = Color(hex: 0xF4CAC8)
    /// "Active" status pill background.
    static let mint = Color(hex: 0xCDF1DC)
    /// "Active" status pill text.
    static let mintText = Color(hex: 0x1D7A4E)
    /// The "F" member avatar / dark text accents.
    static let ink = Color(hex: 0x1A1A1A)
    /// Nav tile background, a shade lighter than `canvas`.
    static let cardSurface = Color(hex: 0xEDEAE6)
}

/// The plain rose-on-blush progress bar used for "Planning" completion in
/// the Trip Detail header — no inline label, unlike `BudgetProgressBar`.
struct BrandProgressTrack: View {
    let fraction: Double
    var fill: Color = BrandPalette.rose
    var track: Color = BrandPalette.roseTrack
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

#Preview("Brand Palette Swatches") {
    let swatches: [(String, Color)] = [
        ("canvas", BrandPalette.canvas),
        ("blush", BrandPalette.blush),
        ("maroon", BrandPalette.maroon),
        ("rose", BrandPalette.rose),
        ("roseTrack", BrandPalette.roseTrack),
        ("mint", BrandPalette.mint),
        ("mintText", BrandPalette.mintText),
        ("ink", BrandPalette.ink),
        ("cardSurface", BrandPalette.cardSurface)
    ]
    return VStack(spacing: 0) {
        ForEach(swatches, id: \.0) { name, color in
            HStack {
                Text(name).font(AppFont.outfit(14, weight: .semibold))
                Spacer()
                Text("TOKYO").font(AppFont.barlowCondensed(20, weight: .bold))
            }
            .padding()
            .background(color)
        }
        BrandProgressTrack(fraction: 0.4).padding()
    }
}
