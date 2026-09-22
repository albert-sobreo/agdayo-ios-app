import SwiftUI

struct TripCardView: View {
    let name: String
    let location: String
    let theme: TripTheme
    let startDate: Date
    let endDate: Date
    let status: TripStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TripCardHeader(name: name, theme: theme, status: status)
            TripCardFooter(location: location, startDate: startDate, endDate: endDate, theme: theme)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .stickerCard(cornerRadius: AppRadius.card, borderColor: theme.borderTint, shadowColor: theme.borderTint)
    }
}

private struct TripCardHeader: View {
    let name: String
    let theme: TripTheme
    let status: TripStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusBadge(status: status)
            Text(name)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.headerBackground)
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
        .font(.caption.weight(.medium))
        .foregroundStyle(theme.accentColor)
    }
}
