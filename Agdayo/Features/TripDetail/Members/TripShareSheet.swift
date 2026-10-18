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
    @State private var isShowingSignIn = false

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

    private var accent: Color { trip.theme.accentColor }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header

                    if !authService.isSignedIn {
                        statusCard(
                            icon: "person.crop.circle.badge.exclamationmark",
                            title: "Sign in required",
                            message: "Sign in to invite friends and sync this trip in real-time."
                        ) {
                            Button {
                                isShowingSignIn = true
                            } label: {
                                Text("Sign In")
                                    .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                        }
                    } else if isLoading {
                        MoneyCard {
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Generating invite code...")
                                    .font(AppFont.outfit(14, relativeTo: .caption))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        }
                    } else if let errorMessage {
                        statusCard(
                            icon: "exclamationmark.triangle.fill",
                            title: "Something went wrong",
                            message: errorMessage
                        ) {
                            Button("Try Again") {
                                Task { await loadCode() }
                            }
                            .buttonStyle(.bordered)
                            .tint(accent)
                        }
                    } else {
                        codeCard
                        shareButton
                        howItWorksCard
                    }
                }
                .padding()
            }
            .background(BrandPalette.canvas.ignoresSafeArea())
            .navigationTitle("Share Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingSignIn) {
                SignInView()
            }
            .task {
                guard authService.isSignedIn else {
                    isLoading = false
                    return
                }
                await loadCode()
            }
            .onChange(of: authService.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    Task { await loadCode() }
                }
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        VStack(spacing: 10) {
            MoneyIconBadge(systemName: "person.2.badge.key.fill", accentColor: accent)
                .scaleEffect(1.3)
                .padding(.top, 6)
            Text("Invite friends")
                .font(AppFont.barlowCondensed(34, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(accent)
            Text("Share this code or link so they can view and edit \"\(trip.name)\" with you.")
                .font(AppFont.outfit(14, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
    }

    /// Sign-in prompt and load errors share one card layout.
    private func statusCard<Action: View>(icon: String, title: String, message: String, @ViewBuilder action: () -> Action) -> some View {
        MoneyCard {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(.orange)
                Text(title)
                    .font(AppFont.barlowCondensed(24, weight: .semibold))
                Text(message)
                    .font(AppFont.outfit(13, relativeTo: .caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                action()
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var codeCard: some View {
        MoneyCard {
            VStack(spacing: 16) {
                Text("INVITE CODE")
                    .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Text(joinCode)
                    .font(AppFont.barlowCondensed(58, weight: .semibold))
                    .tracking(6)
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.smallerCard))

                HStack(spacing: 12) {
                    copyButton(
                        title: hasCopiedCode ? "Copied!" : "Copy Code",
                        icon: hasCopiedCode ? "checkmark" : "doc.on.doc",
                        done: hasCopiedCode
                    ) {
                        UIPasteboard.general.string = joinCode
                        hasCopiedCode = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { hasCopiedCode = false }
                    }
                    copyButton(
                        title: hasCopiedLink ? "Copied!" : "Copy Link",
                        icon: hasCopiedLink ? "checkmark" : "link",
                        done: hasCopiedLink
                    ) {
                        UIPasteboard.general.string = shareURLString
                        hasCopiedLink = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { hasCopiedLink = false }
                    }
                }
            }
        }
    }

    private func copyButton(title: String, icon: String, done: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(done ? Color.appSuccess : accent)
                .background((done ? Color.appSuccess : accent).opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var shareButton: some View {
        ShareLink(
            item: shareMessage,
            subject: Text("Join my trip: \(trip.name)"),
            message: Text("Join my trip to \(trip.location) on Agdayo! Use code: \(joinCode)")
        ) {
            Label("Share Invite", systemImage: "square.and.arrow.up")
                .font(AppFont.outfit(16, weight: .bold, relativeTo: .headline))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(.white)
                .background(accent, in: Capsule())
        }
    }

    private var howItWorksCard: some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 14) {
                MoneySectionHeader(title: "How it works", iconName: "questionmark.circle", accentColor: accent)
                step(1, "Send the 6-character code or link to your travel companion.")
                step(2, "They open Agdayo and choose \"Join Trip with Code\".")
                step(3, "The trip instantly syncs between all members in real-time.")
            }
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(AppFont.barlowCondensed(16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(accent, in: Circle())
            Text(text)
                .font(AppFont.outfit(14, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
