import FirebaseAuth
import FirebaseFirestore

/// Direct client-SDK reads/writes to `users/{uid}` — this app talks to
/// Firestore straight from the client, with no backend server in between.
enum UserDirectoryService {
    private static var usersCollection: CollectionReference {
        Firestore.firestore().collection("users")
    }

    static func fetchProfile(uid: String) async throws -> AppUserProfile? {
        let snapshot = try await usersCollection.document(uid).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: AppUserProfile.self)
    }

    /// Creates the profile document on first sign-in, or just bumps
    /// `updatedAt` on subsequent sign-ins.
    static func ensureUserDocument(for user: FirebaseAuth.User) async throws {
        let documentRef = usersCollection.document(user.uid)
        let snapshot = try await documentRef.getDocument()

        if snapshot.exists {
            try await documentRef.updateData(["updatedAt": FieldValue.serverTimestamp()])
        } else {
            var profile: [String: Any] = [
                "uid": user.uid,
                "displayName": user.displayName ?? user.email ?? "Traveler",
                "email": user.email ?? "",
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ]
            if let photoURL = user.photoURL?.absoluteString {
                profile["photoURL"] = photoURL
            }
            try await documentRef.setData(profile)
        }
    }
}
