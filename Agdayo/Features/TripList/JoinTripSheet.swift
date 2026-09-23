import SwiftUI
import SwiftData
import FirebaseAuth

struct JoinTripSheet: View {
    var initialCode: String = ""
    var onJoined: (Trip) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService

    @State private var inputCode: String = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var isShowingSignIn = false

    init(initialCode: String = "", onJoined: @escaping (Trip) -> Void = { _ in }) {
        self.initialCode = initialCode
        self.onJoined = onJoined
        _inputCode = State(initialValue: initialCode)
    }

    private var cleanedCode: String {
        TripMembershipService.extractJoinCode(from: inputCode)
    }

    private var isValidCode: Bool {
        !cleanedCode.isEmpty && cleanedCode.count >= 4
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Icon & Title
                    VStack(spacing: 8) {
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.appPrimary)
                            .padding(.top, 16)

                        Text("Join a Trip")
                            .font(AppFont.outfit(26, weight: .bold, relativeTo: .title))
                            .foregroundStyle(.primary)

                        Text("Enter the 6-character invitation code or link sent by your friend.")
                            .font(AppFont.outfit(14, relativeTo: .subheadline))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    if !authService.isSignedIn {
                        // Sign In Required Banner
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.exclamationmark")
                                    .font(.title2)
                                    .foregroundStyle(.orange)
                                Text("Sign in required")
                                    .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                            }
                            Text("You need to be signed in to join and sync shared trips.")
                                .font(AppFont.outfit(13, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Button {
                                isShowingSignIn = true
                            } label: {
                                Text("Sign In")
                                    .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.appPrimary)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }

                    // Code Input Box
                    VStack(spacing: 16) {
                        TextField("e.g. 7X9K2P", text: $inputCode)
                            .font(AppFont.outfit(28, weight: .bold, relativeTo: .title2))
                            .monospaced()
                            .multilineTextAlignment(.center)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)
                            .padding()
                            .background(Color(.tertiarySystemFill))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onChange(of: inputCode) { _, _ in
                                errorMessage = nil
                            }

                        // Paste from clipboard button
                        if let pasteboardString = UIPasteboard.general.string,
                           !pasteboardString.isEmpty,
                           inputCode.isEmpty {
                            Button {
                                inputCode = pasteboardString
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.on.clipboard")
                                    Text("Paste from Clipboard")
                                }
                                .font(AppFont.outfit(13, weight: .medium, relativeTo: .caption))
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.appPrimary)
                        }

                        if let errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .font(AppFont.outfit(13, relativeTo: .caption))
                                    .foregroundStyle(.red)
                            }
                            .padding(.horizontal)
                        }

                        Button {
                            Task { await submitJoin() }
                        } label: {
                            HStack {
                                if isJoining {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, 4)
                                }
                                Text(isJoining ? "Joining..." : "Join Trip")
                                    .font(AppFont.outfit(16, weight: .bold, relativeTo: .headline))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isValidCode && authService.isSignedIn && !isJoining ? Color.appPrimary : Color.gray.opacity(0.4))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(!isValidCode || !authService.isSignedIn || isJoining)
                    }
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Join Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingSignIn) {
                SignInView()
            }
        }
    }

    private func submitJoin() async {
        guard let uid = authService.firebaseUser?.uid else {
            errorMessage = "Please sign in before joining a trip."
            return
        }

        isJoining = true
        errorMessage = nil

        do {
            let tripID = try await TripMembershipService.joinTrip(code: cleanedCode, uid: uid)
            if let materialized = await TripDiscoveryService.materializeTrip(tripID: tripID, modelContext: modelContext) {
                isJoining = false
                onJoined(materialized)
                dismiss()
            } else {
                isJoining = false
                errorMessage = "Joined the trip, but could not load trip data. Please pull down on your trips list to refresh."
            }
        } catch {
            isJoining = false
            errorMessage = error.localizedDescription
        }
    }
}
