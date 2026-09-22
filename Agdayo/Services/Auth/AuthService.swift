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

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController:
            return "Couldn't find a screen to present sign-in from."
        case .missingGoogleIDToken:
            return "Google sign-in didn't return an ID token."
        }
    }
}
