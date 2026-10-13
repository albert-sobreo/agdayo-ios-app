import SwiftUI

struct TripHeaderView: View {
    let name: String
    let location: String
    let startDate: Date
    let endDate: Date
    let theme: TripTheme
    let status: TripStatus
    let planningProgress: (completed: Int, total: Int)
    var members: [AppUserProfile] = []
    var isLiveActivityRunning: Bool = false
    let onViewMap: () -> Void
    let onSettings: () -> Void
    var onInvite: () -> Void = {}

    private var headline: Color {
        theme.accentColor.mix(with: .black, by: 0.35)
    }

    private var dayNumber: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.startOfDay(for: startDate)
        return max(1, (calendar.dateComponents([.day], from: start, to: today).day ?? 0) + 1)
    }

    private var numberOfDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        return max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
    }

    private func monthDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().month(.abbreviated).day())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                if status == .active {
                    PillTag(
                        text: "Active · Day \(dayNumber) of \(numberOfDays)".uppercased(),
                        background: theme.lightTintColor,
                        foreground: theme.accentColor
                    )
                } else {
                    StatusBadge(status: status)
                        .textCase(.uppercase)
                        .tracking(2)
                }
                Spacer()
                Button(action: onViewMap) {
                    Label("View on Map", systemImage: "map")
                        .font(AppFont.outfit(12, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(theme.accentColor)
                        .textCase(.uppercase)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(location.uppercased())
                    .font(AppFont.barlowCondensed(72, weight: .ultraLight))
                    .foregroundStyle(headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                HStack(alignment: .center) {
                    Text(name.uppercased())
                        .font(AppFont.barlowCondensed(20, weight: .semibold, relativeTo: .subheadline))
                        .tracking(1)
                        .foregroundStyle(headline)
                        .padding(.trailing, 4)
                    
                    Button(action: onSettings) {
                        Image(systemName: "pencil")
                            .foregroundStyle(headline)
                    }
                    .accessibilityLabel("Trip Settings")
                }
            }

            HStack(spacing: 0) {
                statColumn(label: "Depart", value: monthDay(startDate))
                    .frame(maxWidth: .infinity)

                verticalDivider

                statColumn(label: "Return", value: monthDay(endDate))
                    .frame(maxWidth: .infinity)

                verticalDivider

                statColumn(label: "Days", value: "\(numberOfDays)")
                    .frame(maxWidth: .infinity)
            }

            TripPlanningProgressBar(progress: planningProgress, theme: theme)

            HStack(spacing: 12) {
                if !members.isEmpty {
                    MemberAvatarRow(members: members, theme: theme)
                }
                Button(action: onInvite) {
                    Text("+ Invite".uppercased())
                        .font(AppFont.outfit(12, weight: .semibold, relativeTo: .caption))
                        .tracking(1)
                        .foregroundStyle(theme.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(Capsule().strokeBorder(theme.accentColor.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.headerBackground)
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(theme.accentColor.opacity(0.3))
            .frame(width: 1, height: 28)
            .padding(.horizontal, 12)
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .trackedLabel(10, color: headline.opacity(0.7))
            Text(value.uppercased())
                .font(AppFont.barlowCondensed(36, weight: .light))
                .foregroundStyle(headline)
        }
    }
}

private struct MemberAvatarRow: View {
    let members: [AppUserProfile]
    let theme: TripTheme

    var body: some View {
        HStack(spacing: -8) {
            ForEach(members, id: \.uid) { member in
                MemberAvatar(profile: member, theme: theme)
            }
        }
    }
}

private struct MemberAvatar: View {
    let profile: AppUserProfile
    let theme: TripTheme

    private var monogram: String {
        String(profile.displayName.first ?? "?").uppercased()
    }

    var body: some View {
        Group {
            if let photoURL = profile.photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    monogramView
                }
            } else {
                monogramView
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .accessibilityLabel(profile.displayName)
    }

    private var monogramView: some View {
        Circle()
            .fill(theme.accentColor)
            .overlay(
                Text(monogram)
                    .font(AppFont.outfit(12, weight: .bold, relativeTo: .caption2))
                    .foregroundStyle(.white)
            )
    }
}

private struct TripPlanningProgressBar: View {
    let progress: (completed: Int, total: Int)
    let theme: TripTheme

    private var fraction: Double {
        progress.total == 0 ? 0 : Double(progress.completed) / Double(progress.total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Planning")
                    .trackedLabel(11, color: theme.accentColor.mix(with: .black, by: 0.35).opacity(0.7))
                Spacer()
                Text("\(progress.completed) of \(progress.total) done")
                    .trackedLabel(11, color: theme.accentColor.mix(with: .black, by: 0.35).opacity(0.7))
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.trackColor)
                    Capsule()
                        .fill(theme.accentColor)
                        .frame(width: geometry.size.width * fraction)
                }
            }
            .frame(height: 6)
        }
    }
}
