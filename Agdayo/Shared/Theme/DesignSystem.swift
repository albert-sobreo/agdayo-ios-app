import SwiftUI

/// Corner-radius scale matching the web app's dominant Tailwind radii.
enum AppRadius {
    static let card: CGFloat = 32       // rounded-4xl — big surfaces (trip cards)
    static let smallerCard: CGFloat = 24 // smaller card radius
    static let denseCard: CGFloat = 16  // rounded-2xl — stat tiles, activity cards
    static let sheet: CGFloat = 24      // rounded-t-3xl — bottom sheets
    static let pill: CGFloat = 6        // rounded-md — tags
}

extension View {
    /// The web app's flat "sticker" card: opaque surface, thin themed border,
    /// and a hard offset shadow with zero blur (radius: 0 renders a crisp,
    /// unblurred copy of the shape rather than a soft native shadow).
    func stickerCard(
        cornerRadius: CGFloat = AppRadius.denseCard,
        borderColor: Color = .appSecondary,
        shadowColor: Color = .appSecondary,
        background: Color = Color(.systemBackground)
    ) -> some View {
        self
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 0, x: 2, y: 2)
    }
}

/// Liquid Glass on iOS 26+, falling back to the plain `stickerCard` treatment
/// on iOS 18–25 (the app's minimum deployment target).
struct GlassOrStickerCard: ViewModifier {
    var cornerRadius: CGFloat = AppRadius.denseCard

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26, *) {
                content.glassEffect(in: .rect(cornerRadius: cornerRadius))
            } else {
                content.stickerCard(cornerRadius: cornerRadius)
            }
        }
    }
}

/// Small rounded-rect pill used for statuses, categories, and metadata tags.
struct PillTag: View {
    let text: String
    let background: Color
    let foreground: Color
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
        }
        .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background)
        .foregroundStyle(foreground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
        .accessibilityElement(children: .combine)
    }
}

/// Rounded-full pill button with the web app's `active:scale-95` press feedback.
struct AppButtonStyle: ButtonStyle {
    var background: Color
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(AppFont.outfit(17, weight: .bold))
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .foregroundStyle(foreground)

        Group {
            if #available(iOS 26, *) {
                label.glassEffect(.regular.tint(background).interactive(), in: Capsule())
            } else {
                label.background(background).clipShape(Capsule())
            }
        }
        .scaleEffect(configuration.isPressed ? 0.95 : 1)
        .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var appPrimary: AppButtonStyle { AppButtonStyle(background: .appPrimary) }
    static var appSecondary: AppButtonStyle {
        AppButtonStyle(background: Color(.systemGray5), foreground: .primary)
    }
    static var appDanger: AppButtonStyle { AppButtonStyle(background: .appDanger) }
}
