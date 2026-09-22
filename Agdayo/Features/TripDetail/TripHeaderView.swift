import SwiftUI

struct TripHeaderView: View {
    let name: String
    let location: String
    let startDate: Date
    let endDate: Date
    let theme: TripTheme
    let status: TripStatus
    let planningProgress: (completed: Int, total: Int)
    let onViewMap: () -> Void
    let onSettings: () -> Void

    private var dateRangeText: String {
        let formatter = Date.FormatStyle().month(.abbreviated).day().year()
        return "\(startDate.formatted(formatter)) – \(endDate.formatted(formatter))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                StatusBadge(status: status)
                Spacer()
                Button(action: onViewMap) {
                    PillTag(
                        text: "View on Map",
                        background: theme.lightTintColor,
                        foreground: theme.accentColor,
                        icon: "map"
                    )
                }
                .buttonStyle(.plain)
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Trip Settings")
            }

            Text(name)
                .font(AppFont.matatasOne(36, relativeTo: .largeTitle))
                .foregroundStyle(theme.accentColor.mix(with: .black, by: 0.35))
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 4) {
                Label(location, systemImage: "mappin.and.ellipse")
                Label(dateRangeText, systemImage: "calendar")
            }
            .font(AppFont.outfit(15, relativeTo: .subheadline))
            .foregroundStyle(.secondary)

            TripPlanningProgressBar(progress: planningProgress, theme: theme)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.headerBackground)
    }
}

private struct TripPlanningProgressBar: View {
    let progress: (completed: Int, total: Int)
    let theme: TripTheme

    private var fraction: Double {
        progress.total == 0 ? 0 : Double(progress.completed) / Double(progress.total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Planning Progress: \(progress.completed)/\(progress.total)")
                .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                .foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.trackColor)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.accentColor)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 8)
        }
    }
}
