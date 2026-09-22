import Foundation

/// Mirrors the `users/{uid}` Firestore document this app writes directly via
/// the client SDK — designed fresh for iOS, not shared with the web app's
/// separate Firebase project/schema.
struct AppUserProfile: Codable {
    var uid: String
    var displayName: String
    var email: String
    var photoURL: String?
    var createdAt: Date
    var updatedAt: Date
}
