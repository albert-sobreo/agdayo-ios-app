import SwiftUI

struct MemberRowView: View {
    let member: TripMemberRecord
    let theme: TripTheme
    let canRemove: Bool
    let isCurrentUser: Bool
    var onRemove: () -> Void = {}

    @State private var isShowingConfirmRemove = false

    private var monogram: String {
        String(member.profile.displayName.first ?? "?").uppercased()
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if let photoURL = member.profile.photoURL, let url = URL(string: photoURL) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        monogramView
                    }
                } else {
                    monogramView
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            // Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.profile.displayName)
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(.primary)

                    if isCurrentUser {
                        Text("(You)")
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }

                if !member.profile.email.isEmpty {
                    Text(member.profile.email)
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Role Badge
            if member.isOwner {
                HStack(spacing: 4) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 10))
                    Text("Owner")
                        .font(AppFont.outfit(11, weight: .bold, relativeTo: .caption2))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(theme.lightTintColor)
                .foregroundStyle(theme.accentColor)
                .clipShape(Capsule())
            } else {
                Text("Member")
                    .font(AppFont.outfit(11, weight: .medium, relativeTo: .caption2))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.secondarySystemFill))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }

            // Remove Button (if owner is viewing a member)
            if canRemove {
                Button(role: .destructive) {
                    isShowingConfirmRemove = true
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red.opacity(0.8))
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(member.profile.displayName)")
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog(
            "Remove \(member.profile.displayName)?",
            isPresented: $isShowingConfirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove Member", role: .destructive) {
                onRemove()
            }
        } message: {
            Text("They will no longer be able to view or edit this trip.")
        }
    }

    private var monogramView: some View {
        Circle()
            .fill(theme.accentColor)
            .overlay(
                Text(monogram)
                    .font(AppFont.outfit(16, weight: .bold, relativeTo: .body))
                    .foregroundStyle(.white)
            )
    }
}
