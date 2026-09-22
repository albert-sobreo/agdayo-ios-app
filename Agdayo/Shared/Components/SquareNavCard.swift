import SwiftUI

/// Icon + count + title navigation tile, matching the web app's AdvSquareCard
/// (icon top, label pill, bold title) used for the trip detail section row.
struct SquareNavCard: View {
    let iconName: String
    let subtitle: String
    let title: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 28))
                .foregroundStyle(accentColor)
            Spacer(minLength: 0)
            Text(subtitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(minWidth: 128, minHeight: 128, alignment: .leading)
        .glassEffect(
            in: .rect(cornerRadius: AppRadius.card)
        )
    }
}
