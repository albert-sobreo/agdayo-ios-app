import SwiftUI

/// A card that opens Connect Claude, for places people start planning (new
/// trip, trip page), so it's found without digging into Profile.
struct PlanWithClaudeCard: View {
    var accentColor: Color = .appPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 40, height: 40)
                    .background(accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan with Claude")
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(.primary)
                    Text("Chat your trip, and Claude writes it into Agdayo. Free plan works.")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows how to connect Claude to Agdayo")
    }
}

/// Connect Claude in its own sheet, with a Done button.
struct ConnectClaudeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ConnectClaudeView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
