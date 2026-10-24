import SwiftUI

/// Edit-sheet building blocks: each group of inputs is a card (the same glass
/// card as the Plan My Day setup page) with a header, and each input sits
/// transparent under a small label.

/// A titled card holding a group of `FormField`s.
struct FormCard<Content: View>: View {
    let title: String
    let icon: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 12) {
                MoneySectionHeader(title: title, iconName: icon, accentColor: accent)
                content
            }
        }
    }
}

/// One input, with an optional small label above it.
/// Controls that carry their own label (pickers, date pickers, toggles) can
/// leave `label` off.
struct FormField<Content: View>: View {
    var label: String?
    @ViewBuilder let content: Content

    init(_ label: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(AppFont.outfit(10, weight: .semibold, relativeTo: .caption2))
                    .textCase(.uppercase)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            // No fill, so the card's glass shows through (like the Plan My Day
            // day picker); a hairline underneath keeps each input findable.
            content
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(height: 0.5)
                }
        }
    }
}

extension View {
    /// For sheets with a lot of input: swiping down can't close them, and the
    /// Cancel button asks first (the sheet decides when, via `isPresented`).
    func confirmsDiscard(isPresented: Binding<Bool>, onDiscard: @escaping () -> Void) -> some View {
        self
            .interactiveDismissDisabled()
            .confirmationDialog("Discard changes?", isPresented: isPresented, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive, action: onDiscard)
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("What you entered won't be saved.")
            }
    }
}
