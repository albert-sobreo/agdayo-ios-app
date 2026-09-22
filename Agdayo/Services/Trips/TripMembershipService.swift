import FirebaseFirestore

/// Direct client-SDK reads/writes to `trips/{tripID}` + its `members`
/// subcollection — the local `Trip.id` doubles as the Firestore document ID.
/// Mirrors the pattern from `UserDirectoryService`.
enum TripMembershipService {
    private static var tripsCollection: CollectionReference {
        Firestore.firestore().collection("trips")
    }

    static func createTripRecord(
        tripID: UUID,
        ownerUID: String,
        name: String,
        location: String,
        theme: String,
        startDate: Date,
        endDate: Date,
        overallBudget: Double,
        currency: String,
        tripDescription: String
    ) async throws {
        let tripRef = tripsCollection.document(tripID.uuidString)
        try await tripRef.setData([
            "ownerUID": ownerUID,
            "name": name,
            "location": location,
            "theme": theme,
            "startDate": startDate,
            "endDate": endDate,
            "overallBudget": overallBudget,
            "currency": currency,
            "tripDescription": tripDescription,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ])
        try await tripRef.collection("members").document(ownerUID).setData([
            "uid": ownerUID,
            "role": "owner",
            "joinedAt": FieldValue.serverTimestamp(),
        ])
        try await Firestore.firestore().collection("users").document(ownerUID).updateData([
            "memberOfTripIDs": FieldValue.arrayUnion([tripID.uuidString])
        ])
    }

    static func updateTripRecord(
        tripID: UUID,
        name: String,
        location: String,
        theme: String,
        startDate: Date,
        endDate: Date,
        overallBudget: Double,
        currency: String,
        tripDescription: String
    ) async throws {
        try await tripsCollection.document(tripID.uuidString).updateData([
            "name": name,
            "location": location,
            "theme": theme,
            "startDate": startDate,
            "endDate": endDate,
            "overallBudget": overallBudget,
            "currency": currency,
            "tripDescription": tripDescription,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    static func deleteTripRecord(tripID: UUID) async throws {
        let tripRef = tripsCollection.document(tripID.uuidString)
        let members = try await tripRef.collection("members").getDocuments()
        for member in members.documents {
            try await member.reference.delete()
        }
        try await tripRef.delete()
    }

    /// Finds every trip a UID is a member of, via the denormalized
    /// `memberOfTripIDs` array on their own `users/{uid}` doc — a plain
    /// single-document read, deliberately avoiding a Firestore
    /// collection-group query (those have persistent, hard-to-diagnose
    /// rules/index quirks; a self-owned array field is simpler and more
    /// robust for this "which trips am I in" lookup).
    static func fetchMemberTripIDs(uid: String) async throws -> [UUID] {
        let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
        guard let ids = snapshot.data()?["memberOfTripIDs"] as? [String] else { return [] }
        return ids.compactMap { UUID(uuidString: $0) }
    }

    static func fetchTripFields(tripID: UUID) async throws -> TripFieldsDTO? {
        let snapshot = try await tripsCollection.document(tripID.uuidString).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: TripFieldsDTO.self)
    }
}
