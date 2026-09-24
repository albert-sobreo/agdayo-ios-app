import FirebaseFirestore

enum TripJoinError: LocalizedError {
    case invalidCode
    case tripNotFound
    case alreadyMember
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .invalidCode:
            return "The invitation code is invalid or does not exist."
        case .tripNotFound:
            return "The trip associated with this code could not be found."
        case .alreadyMember:
            return "You are already a member of this trip."
        case .notSignedIn:
            return "Please sign in to join a trip."
        }
    }
}

/// Direct client-SDK reads/writes to `trips/{tripID}` + its `members`
/// subcollection — the local `Trip.id` doubles as the Firestore document ID.
/// Mirrors the pattern from `UserDirectoryService`.
enum TripMembershipService {
    private static var tripsCollection: CollectionReference {
        Firestore.firestore().collection("trips")
    }

    private static var joinCodesCollection: CollectionReference {
        Firestore.firestore().collection("tripJoinCodes")
    }

    static func generateRandomCode(length: Int = 6) -> String {
        let chars = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }

    static func extractJoinCode(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let codeItem = components.queryItems?.first(where: { $0.name.lowercased() == "code" })?.value {
            return codeItem.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        return trimmed.uppercased()
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
        tripDescription: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        visitedCountry: String? = nil,
        visitedProvince: String? = nil,
        visitedCity: String? = nil
    ) async throws {
        let joinCode = generateRandomCode()
        let tripRef = tripsCollection.document(tripID.uuidString)
        var data: [String: Any] = [
            "ownerUID": ownerUID,
            "name": name,
            "location": location,
            "theme": theme,
            "startDate": startDate,
            "endDate": endDate,
            "overallBudget": overallBudget,
            "currency": currency,
            "tripDescription": tripDescription,
            "joinCode": joinCode,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let latitude { data["latitude"] = latitude }
        if let longitude { data["longitude"] = longitude }
        if let visitedCountry { data["visitedCountry"] = visitedCountry }
        if let visitedProvince { data["visitedProvince"] = visitedProvince }
        if let visitedCity { data["visitedCity"] = visitedCity }
        try await tripRef.setData(data)
        try await joinCodesCollection.document(joinCode).setData([
            "tripID": tripID.uuidString,
            "createdAt": FieldValue.serverTimestamp(),
        ])
        try await tripRef.collection("members").document(ownerUID).setData([
            "uid": ownerUID,
            "role": "owner",
            "joinedAt": FieldValue.serverTimestamp(),
        ])
        try await Firestore.firestore().collection("users").document(ownerUID).setData([
            "memberOfTripIDs": FieldValue.arrayUnion([tripID.uuidString])
        ], merge: true)
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
        tripDescription: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        visitedCountry: String? = nil,
        visitedProvince: String? = nil,
        visitedCity: String? = nil
    ) async throws {
        var data: [String: Any] = [
            "name": name,
            "location": location,
            "theme": theme,
            "startDate": startDate,
            "endDate": endDate,
            "overallBudget": overallBudget,
            "currency": currency,
            "tripDescription": tripDescription,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let latitude { data["latitude"] = latitude }
        if let longitude { data["longitude"] = longitude }
        if let visitedCountry { data["visitedCountry"] = visitedCountry }
        if let visitedProvince { data["visitedProvince"] = visitedProvince }
        if let visitedCity { data["visitedCity"] = visitedCity }
        try await tripsCollection.document(tripID.uuidString).updateData(data)
    }

    static func deleteTripRecord(tripID: UUID) async throws {
        let tripRef = tripsCollection.document(tripID.uuidString)
        if let data = try? await tripRef.getDocument().data(),
           let joinCode = data["joinCode"] as? String {
            try? await joinCodesCollection.document(joinCode).delete()
        }
        let members = try await tripRef.collection("members").getDocuments()
        for member in members.documents {
            try await member.reference.delete()
        }
        try await tripRef.delete()
    }

    /// Finds or creates a 6-character join code for a trip.
    static func getOrCreateJoinCode(for tripID: UUID) async throws -> String {
        let tripRef = tripsCollection.document(tripID.uuidString)
        let snapshot = try await tripRef.getDocument()
        if let existing = snapshot.data()?["joinCode"] as? String, !existing.isEmpty {
            return existing
        }

        let code = generateRandomCode()
        try await joinCodesCollection.document(code).setData([
            "tripID": tripID.uuidString,
            "createdAt": FieldValue.serverTimestamp(),
        ])
        try await tripRef.updateData([
            "joinCode": code,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
        return code
    }

    /// Validates an invite code and adds the user to the trip members list.
    static func joinTrip(code: String, uid: String) async throws -> UUID {
        let normalizedCode = extractJoinCode(from: code)
        guard !normalizedCode.isEmpty else {
            throw TripJoinError.invalidCode
        }

        let codeDoc = try await joinCodesCollection.document(normalizedCode).getDocument()
        guard codeDoc.exists, let tripIDString = codeDoc.data()?["tripID"] as? String, let tripID = UUID(uuidString: tripIDString) else {
            throw TripJoinError.invalidCode
        }

        let tripRef = tripsCollection.document(tripIDString)
        let tripDoc = try await tripRef.getDocument()
        guard tripDoc.exists else {
            throw TripJoinError.tripNotFound
        }

        let existingTripIDs = (try? await fetchMemberTripIDs(uid: uid)) ?? []
        if existingTripIDs.contains(tripID) {
            throw TripJoinError.alreadyMember
        }

        try await tripRef.collection("members").document(uid).setData([
            "uid": uid,
            "role": "member",
            "joinedAt": FieldValue.serverTimestamp(),
        ])
        try await Firestore.firestore().collection("users").document(uid).setData([
            "memberOfTripIDs": FieldValue.arrayUnion([tripIDString])
        ], merge: true)

        return tripID
    }

    /// Removes a member from a trip (either owner kicks or member leaves).
    static func removeMember(tripID: UUID, uid: String) async throws {
        let tripRef = tripsCollection.document(tripID.uuidString)
        try await tripRef.collection("members").document(uid).delete()
        try? await Firestore.firestore().collection("users").document(uid).setData([
            "memberOfTripIDs": FieldValue.arrayRemove([tripID.uuidString])
        ], merge: true)
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

    /// Session-scoped cache of `(tripID, uid)` pairs already confirmed to
    /// have a membership doc — `TripDetailView` calls `ensureMembership` on
    /// every single visit to a trip, and without this it would re-read the
    /// `members/{uid}` doc every single time, forever, even though it only
    /// ever needs fixing once (the one-time race this guards against).
    @MainActor
    private static var verifiedMemberships: Set<String> = []

    /// Idempotently ensures the given user actually has a `members` doc for
    /// this trip. Guards against a trip that looks synced locally
    /// (`ownerUID`/`memberOfTripIDs` set) but whose membership write
    /// silently failed partway through `createTripRecord`/`joinTrip` (e.g.
    /// no network at that exact moment) — without it, `isMember()` fails
    /// the security-rule check forever and every future write to that
    /// trip's content gets rejected as permission-denied. Safe to call
    /// unconditionally: the rules already allow anyone to create their own
    /// `members/{uid}` doc as long as the trip exists.
    @MainActor
    static func ensureMembership(tripID: UUID, uid: String, role: String) async throws {
        let key = "\(tripID.uuidString)-\(uid)"
        guard !verifiedMemberships.contains(key) else { return }

        let memberRef = tripsCollection.document(tripID.uuidString).collection("members").document(uid)
        let snapshot = try await memberRef.getDocument()
        if !snapshot.exists {
            try await memberRef.setData([
                "uid": uid,
                "role": role,
                "joinedAt": FieldValue.serverTimestamp(),
            ])
            try await Firestore.firestore().collection("users").document(uid).setData([
                "memberOfTripIDs": FieldValue.arrayUnion([tripID.uuidString])
            ], merge: true)
        }
        verifiedMemberships.insert(key)
    }

    static func fetchTripFields(tripID: UUID) async throws -> TripFieldsDTO? {
        let snapshot = try await tripsCollection.document(tripID.uuidString).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: TripFieldsDTO.self)
    }
}
