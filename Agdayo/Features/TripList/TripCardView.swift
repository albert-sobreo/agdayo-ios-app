import SwiftUI

struct TripCardView: View {
    let name: String
    let location: String
    let theme: TripTheme
    let startDate: Date
    let endDate: Date
    let status: TripStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            TripCardHeader(
                name: name,
                location: location,
                theme: theme,
                status: status
            )

            TripCardFooter(
                location: location,
                startDate: startDate,
                endDate: endDate,
                theme: theme
            )
            .padding()
        }
        .clipShape(
            RoundedRectangle(cornerRadius: AppRadius.card)
        )
        .glassEffect(
            .regular.tint(theme.accentColor.opacity(0.10)),
            in: .rect(cornerRadius: AppRadius.card)
        )
    }
}

private struct TripCardHeader: View {
    let name: String
    let location: String
    let theme: TripTheme
    let status: TripStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBadge(status: status)

            VStack(alignment: .leading, spacing: 5) {
                Text(name)
                    .font(AppFont.outfit(26, weight: .bold, relativeTo: .title2))
                    .foregroundStyle(
                        theme.accentColor.mix(with: .black, by: 0.35)
                    )
                    .lineLimit(1)
                Text(location)
                    .font(AppFont.outfit(14, weight: .regular, relativeTo: .subheadline))
                    .foregroundStyle(
                        theme.accentColor.mix(with: .black, by: 0.35)
                    )
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TripCardFooter: View {
    let location: String
    let startDate: Date
    let endDate: Date
    let theme: TripTheme

    private var dateRangeText: String {
        let formatter = Date.FormatStyle().month(.abbreviated).day()
        return "\(startDate.formatted(formatter)) – \(endDate.formatted(formatter))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(dateRangeText, systemImage: "calendar")
            Label(location, systemImage: "mappin.and.ellipse")
        }
        .font(AppFont.outfit(12, weight: .medium, relativeTo: .caption))
        .foregroundStyle(theme.accentColor)
    }
}
