import SwiftUI

/// A glowing highlight band sweeping across the text, repeating forever —
/// the "AI is thinking" loading state used while generation is in flight.
/// Pure `foregroundStyle` animation (no overlay/mask layering), since
/// `LinearGradient`'s `UnitPoint` start/end are themselves animatable.
struct ShimmerText: View {
    let text: String
    var font: Font
    var tint: Color = .appPrimary

    @State private var isAnimating = false

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(
                LinearGradient(
                    colors: [tint.opacity(0.55), tint, tint.opacity(0.55)],
                    startPoint: isAnimating ? .trailing : .leading,
                    endPoint: isAnimating ? UnitPoint(x: 2.2, y: 0.5) : UnitPoint(x: -1.2, y: 0.5)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}
