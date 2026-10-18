import SwiftUI

/// Widths shared by the activity rows and the travel-time rows between them,
/// so the connecting line stays one straight line down the day.
enum ItineraryRail {
    static let timeWidth: CGFloat = 56
    static let railWidth: CGFloat = 24
    /// Where the content starts, measured from the row's leading edge.
    static var contentInset: CGFloat { timeWidth + railWidth }
}

/// The line that joins one stop to the next: a soft vertical stroke in the
/// trip's color, centered in the rail column and filling the row's height.
struct ItineraryRailLine: View {
    let accentColor: Color

    var body: some View {
        Rectangle()
            .fill(accentColor.opacity(0.35))
            .frame(width: 2)
            .frame(width: ItineraryRail.railWidth)
            .frame(maxHeight: .infinity)
    }
}

/// One activity in the itinerary, laid out like a Plan My Day stop: the time
/// in the trip's color on the left, a dot on the connecting line, then the
/// place with its icon and name, an English translation when there is one,
/// where it is, and what it costs.
struct ActivityRowView: View {
    let title: String
    let location: String
    let cost: Double?
    let costCurrency: String?
    let costNote: String?
    let iconName: String
    let time: Date
    /// English translation of `title`, when the place name is in another language.
    var englishTitle: String? = nil
    /// The trip's color.
    let accentColor: Color
    /// First and last stop of the day: the line starts and ends at the dot.
    var isFirst = false
    var isLast = false

    private let verticalPadding: CGFloat = 12
    private let dotSize: CGFloat = 10

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(time, format: .dateTime.hour().minute())
                .font(AppFont.barlowCondensed(18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: ItineraryRail.timeWidth, alignment: .leading)
                .padding(.vertical, verticalPadding)

            rail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: iconName)
                        .foregroundStyle(accentColor)
                    Text(title)
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(.primary)
                }

                if let englishTitle {
                    Label(englishTitle, systemImage: "globe")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(accentColor)
                }

                if !location.isEmpty {
                    Text(location)
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let cost {
                    HStack(spacing: 4) {
                        Text(cost.formattedCurrency(code: costCurrency ?? "PHP"))
                            .font(AppFont.outfit(12, weight: .medium, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                        if let costNote, !costNote.isEmpty {
                            Text(costNote)
                                .font(AppFont.outfit(12, relativeTo: .caption))
                                .foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                }
            }
            .padding(.vertical, verticalPadding)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.vertical, verticalPadding)
        }
        .contentShape(Rectangle())
    }

    /// A dot level with the first line of text, with the line running up to
    /// the previous stop and down to the next one.
    private var rail: some View {
        VStack(spacing: 0) {
            // Reaches the dot's center from the top of the row, or nothing on
            // the first stop.
            Rectangle()
                .fill(accentColor.opacity(isFirst ? 0 : 0.35))
                .frame(width: 2, height: verticalPadding + 4)
            Circle()
                .fill(accentColor)
                .frame(width: dotSize, height: dotSize)
            Rectangle()
                .fill(accentColor.opacity(isLast ? 0 : 0.35))
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(width: ItineraryRail.railWidth)
    }
}
