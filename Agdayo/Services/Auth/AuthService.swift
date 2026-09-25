import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import Observation
import UIKit

/// Wraps Firebase Auth for Google + email/password sign-in. Sign-in is
/// optional and deferred app-wide — this only gets used once the user taps
/// "Sign In" from Profile, never at launch.
@Observable
final class AuthService {
    private(set) var firebaseUser: FirebaseAuth.User?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    var isSignedIn: Bool { firebaseUser != nil }

    init() {
        firebaseUser = Auth.auth().currentUser
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.firebaseUser = user
        }
    }

    deinit {
        if let authStateHandle {
            Auth.auth().removeStateDidChangeListener(authStateHandle)
        }
    }

    func signInWithGoogle() async throws {
        guard let presentingViewController = Self.topViewController() else {
            throw AuthServiceError.noPresentingViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthServiceError.missingGoogleIDToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        try await UserDirectoryService.ensureUserDocument(for: authResult.user)
    }

    func signUp(email: String, password: String) async throws {
        let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
        try await UserDirectoryService.ensureUserDocument(for: authResult.user)
    }

    func signIn(email: String, password: String) async throws {
        let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
        try await UserDirectoryService.ensureUserDocument(for: authResult.user)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    /// The signed-in user's provider, e.g. `"google.com"` or `"password"` —
    /// used to pick the right re-authentication flow if account deletion
    /// requires a fresher session (see `deleteAccount()`).
    var signInProviderID: String? {
        firebaseUser?.providerData.first?.providerID
    }

    /// Deletes every trip this account owns, removes it from every trip it's
    /// merely a member of, deletes its `users/{uid}` profile document, then
    /// deletes the Firebase Auth account itself. Firestore cleanup happens
    /// first since it needs to be authenticated as this user to pass the
    /// security rules' "only the account owner can do this" checks — once
    /// `user.delete()` succeeds, that's no longer possible.
    ///
    /// Firebase requires a "recent" sign-in to delete an account; if this
    /// session isn't fresh enough, this throws `AuthServiceError
    /// .requiresRecentLogin` so the caller can re-authenticate (see
    /// `reauthenticateWithGoogle()`/`reauthenticateWithPassword(_:)`) and
    /// call `deleteAccount()` again — the Firestore cleanup above is
    /// idempotent, so repeating it is harmless.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await Self.cleanUpAccountData(uid: user.uid)
        do {
            try await user.delete()
        } catch {
            if let code = AuthErrorCode(rawValue: (error as NSError).code), code == .requiresRecentLogin {
                throw AuthServiceError.requiresRecentLogin
            }
            throw error
        }
    }

    /// Re-establishes a fresh Google session so a subsequent `deleteAccount()`
    /// retry passes Firebase's recent-login requirement.
    func reauthenticateWithGoogle() async throws {
        guard let user = Auth.auth().currentUser else { return }
        guard let presentingViewController = Self.topViewController() else {
            throw AuthServiceError.noPresentingViewController
        }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthServiceError.missingGoogleIDToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        try await user.reauthenticate(with: credential)
    }

    /// Same idea as `reauthenticateWithGoogle()`, for email/password accounts
    /// — the caller has to prompt for the password again since Firebase
    /// never exposes the current one.
    func reauthenticateWithPassword(_ password: String) async throws {
        guard let user = Auth.auth().currentUser, let email = user.email else { return }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await user.reauthenticate(with: credential)
    }

    /// Trips owned by this account are deleted outright (matching
    /// `TripSettingsView`'s own "Delete Trip" semantics — there's no
    /// ownership-transfer feature); trips it's merely a member of are left
    /// intact for the other members, with this account just removed from
    /// `members`.
    private static func cleanUpAccountData(uid: String) async throws {
        let tripIDs = (try? await TripMembershipService.fetchMemberTripIDs(uid: uid)) ?? []
        for tripID in tripIDs {
            if let fields = try? await TripMembershipService.fetchTripFields(tripID: tripID), fields.ownerUID == uid {
                try? await TripMembershipService.deleteTripRecord(tripID: tripID)
            } else {
                try? await TripMembershipService.removeMember(tripID: tripID, uid: uid)
            }
        }
        try? await UserDirectoryService.deleteProfile(uid: uid)
    }

    private static func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            let rootViewController = windowScene.windows.first(where: \.isKeyWindow)?.rootViewController
        else { return nil }

        var topController = rootViewController
        while let presented = topController.presentedViewController {
            topController = presented
        }
        return topController
    }
}

enum AuthServiceError: LocalizedError {
    case noPresentingViewController
    case missingGoogleIDToken
    case requiresRecentLogin

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController:
            return "Couldn't find a screen to present sign-in from."
        case .missingGoogleIDToken:
            return "Google sign-in didn't return an ID token."
        case .requiresRecentLogin:
            return "For your security, please sign in again to confirm this action."
        }
    }
}
