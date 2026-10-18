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

    /// Creates the profile document on first sign-in. On subsequent sign-ins,
    /// also refreshes `photoURL` (in addition to `updatedAt`) — otherwise an
    /// account created before a Google photo was attached (or before this
    /// field existed) would be stuck without one forever, even though
    /// `FirebaseAuth.User.photoURL` has it every time they sign in.
    static func ensureUserDocument(for user: FirebaseAuth.User) async throws {
        let documentRef = usersCollection.document(user.uid)
        let snapshot = try await documentRef.getDocument()

        var data: [String: Any] = ["updatedAt": FieldValue.serverTimestamp()]
        if let photoURL = user.photoURL?.absoluteString {
            data["photoURL"] = photoURL
        }

        if snapshot.exists {
            // An account first saved before a real name was known only has the
            // email or "Traveler" as its display name; replace that fallback
            // as soon as the account has an actual name.
            let stored = (snapshot.data()?["displayName"] as? String) ?? ""
            let storedEmail = (snapshot.data()?["email"] as? String) ?? ""
            let isFallback = stored.isEmpty || stored == "Traveler" || stored == storedEmail || stored.contains("@")
            if isFallback, let name = user.displayName, !name.isEmpty, name != stored {
                data["displayName"] = name
            }
            try await documentRef.updateData(data)
        } else {
            data["uid"] = user.uid
            data["displayName"] = user.displayName ?? user.email ?? "Traveler"
            data["email"] = user.email ?? ""
            data["createdAt"] = FieldValue.serverTimestamp()
            try await documentRef.setData(data)
        }
    }

    /// Makes `name` the account's name everywhere: the Firebase Auth profile
    /// and the `users/{uid}` document that trip members' names are read from.
    static func updateDisplayName(_ name: String, for user: FirebaseAuth.User) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if user.displayName != trimmed {
            let change = user.createProfileChangeRequest()
            change.displayName = trimmed
            try await change.commitChanges()
        }
        try await usersCollection.document(user.uid).setData(
            ["displayName": trimmed, "updatedAt": FieldValue.serverTimestamp()],
            merge: true
        )
    }

    /// Part of account deletion (see `AuthService.deleteAccount()`).
    static func deleteProfile(uid: String) async throws {
        try await usersCollection.document(uid).delete()
    }
}
