import SwiftUI

struct TripShareSheet: View {
    let trip: Trip
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService

    @State private var joinCode: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var hasCopiedCode = false
    @State private var hasCopiedLink = false

    private var shareURLString: String {
        guard !joinCode.isEmpty else { return "" }
        return "agdayo://join?code=\(joinCode)"
    }

    private var shareMessage: String {
        guard !joinCode.isEmpty else { return "" }
        return """
        Join my trip "\(trip.name)" to \(trip.location) on Agdayo!
        Invite Code: \(joinCode)
        Link: \(shareURLString)
        """
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header card
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.badge.key.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(trip.theme.accentColor)
                            .padding(.top, 8)

                        Text("Invite Friends")
                            .font(AppFont.outfit(24, weight: .bold, relativeTo: .title2))
                            .foregroundStyle(.primary)

                        Text("Share this code or link with friends so they can view and edit \"\(trip.name)\" with you.")
                            .font(AppFont.outfit(14, relativeTo: .subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }

                    if isLoading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Generating invite code...")
                                .font(AppFont.outfit(14, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else if let errorMessage {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
                                .foregroundStyle(.orange)
                            Text(errorMessage)
                                .font(AppFont.outfit(14, relativeTo: .body))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Try Again") {
                                Task { await loadCode() }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                    } else {
                        // Join Code Box
                        VStack(spacing: 16) {
                            Text("INVITE CODE")
                                .font(AppFont.outfit(12, weight: .bold, relativeTo: .caption))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)

                            Text(joinCode)
                                .font(AppFont.outfit(38, weight: .bold, relativeTo: .largeTitle))
                                .monospaced()
                                .tracking(4)
                                .foregroundStyle(trip.theme.accentColor)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(trip.theme.lightTintColor)
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                            HStack(spacing: 12) {
                                Button {
                                    UIPasteboard.general.string = joinCode
                                    hasCopiedCode = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        hasCopiedCode = false
                                    }
                                } label: {
                                    Label(
                                        hasCopiedCode ? "Copied Code!" : "Copy Code",
                                        systemImage: hasCopiedCode ? "checkmark" : "doc.on.doc"
                                    )
                                    .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.bordered)
                                .tint(hasCopiedCode ? .green : trip.theme.accentColor)

                                Button {
                                    UIPasteboard.general.string = shareURLString
                                    hasCopiedLink = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        hasCopiedLink = false
                                    }
                                } label: {
                                    Label(
                                        hasCopiedLink ? "Copied Link!" : "Copy Link",
                                        systemImage: hasCopiedLink ? "checkmark" : "link"
                                    )
                                    .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.bordered)
                                .tint(hasCopiedLink ? .green : trip.theme.accentColor)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)

                        // Native ShareLink Button
                        ShareLink(
                            item: shareMessage,
                            subject: Text("Join my trip: \(trip.name)"),
                            message: Text("Join my trip to \(trip.location) on Agdayo! Use code: \(joinCode)")
                        ) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share Invite Link")
                                    .font(AppFont.outfit(16, weight: .bold, relativeTo: .headline))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(trip.theme.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)

                        // Instructions
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How it works")
                                .font(AppFont.outfit(14, weight: .bold, relativeTo: .subheadline))
                                .foregroundStyle(.primary)

                            HStack(alignment: .top, spacing: 12) {
                                Text("1")
                                    .font(AppFont.outfit(12, weight: .bold, relativeTo: .caption))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(trip.theme.accentColor)
                                    .clipShape(Circle())
                                Text("Send the 6-character code or link to your travel companion.")
                                    .font(AppFont.outfit(13, relativeTo: .caption))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(alignment: .top, spacing: 12) {
                                Text("2")
                                    .font(AppFont.outfit(12, weight: .bold, relativeTo: .caption))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(trip.theme.accentColor)
                                    .clipShape(Circle())
                                Text("They open Agdayo and choose \"Join Trip with Code\".")
                                    .font(AppFont.outfit(13, relativeTo: .caption))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(alignment: .top, spacing: 12) {
                                Text("3")
                                    .font(AppFont.outfit(12, weight: .bold, relativeTo: .caption))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(trip.theme.accentColor)
                                    .clipShape(Circle())
                                Text("The trip instantly syncs between all members in real-time.")
                                    .font(AppFont.outfit(13, relativeTo: .caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Share Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadCode()
            }
        }
    }

    private func loadCode() async {
        isLoading = true
        errorMessage = nil
        do {
            let code = try await TripMembershipService.getOrCreateJoinCode(for: trip.id)
            self.joinCode = code
            self.isLoading = false
        } catch {
            self.errorMessage = "Could not load invite code: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
}
