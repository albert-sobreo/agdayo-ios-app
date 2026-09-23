import FirebaseFirestore

/// Generic Firestore CRUD + realtime listening for a trip's content
/// subcollections (activities, accommodations, etc.) — model-specific field
/// mapping lives in each model's own DTO file, not here.
enum FirestoreCollectionSync {
    private static func collection(tripID: UUID, name: String) -> CollectionReference {
        Firestore.firestore().collection("trips").document(tripID.uuidString).collection(name)
    }

    /// Full overwrite of a document — used for both create and update, since
    /// `setData(from:)` already does a full replace either way.
    static func push<T: Encodable>(tripID: UUID, collection name: String, docID: UUID, data: T) async throws {
        try await collection(tripID: tripID, name: name).document(docID.uuidString).setData(from: data)
    }

    static func pushDelete(tripID: UUID, collection name: String, docID: UUID) async throws {
        try await collection(tripID: tripID, name: name).document(docID.uuidString).delete()
    }

    /// Same as above, for subcollections keyed by a non-UUID document ID
    /// (e.g. `liveLocations`, keyed by Firebase uid).
    static func push<T: Encodable>(tripID: UUID, collection name: String, docID: String, data: T) async throws {
        try await collection(tripID: tripID, name: name).document(docID).setData(from: data)
    }

    static func pushDelete(tripID: UUID, collection name: String, docID: String) async throws {
        try await collection(tripID: tripID, name: name).document(docID).delete()
    }

    /// One-shot fetch of every document in a subcollection — used when
    /// materializing a trip locally for the first time (e.g. a newly
    /// discovered trip you were added to), as opposed to `listen` which is
    /// for ongoing realtime updates.
    static func fetchAll<T: Decodable>(tripID: UUID, collection name: String, as type: T.Type) async throws -> [(id: String, data: T)] {
        let snapshot = try await collection(tripID: tripID, name: name).getDocuments()
        return snapshot.documents.compactMap { doc in
            guard let data = try? doc.data(as: T.self) else { return nil }
            return (doc.documentID, data)
        }
    }

    /// Listens to the `trips/{tripID}` document itself (not a subcollection).
    /// Calls back with `nil` only when the document itself is confirmed gone
    /// (e.g. the owner deleted the trip from another device) — a `nil`
    /// snapshot (network drop, or permission-denied after signing out) is
    /// just ignored rather than treated as deletion, otherwise the local
    /// trip would get wiped every time the listener hits a transient error.
    static func listenTripDocument<T: Decodable>(
        tripID: UUID,
        as type: T.Type,
        onChange: @escaping (T?) -> Void
    ) -> ListenerRegistration {
        Firestore.firestore().collection("trips").document(tripID.uuidString).addSnapshotListener { snapshot, _ in
            guard let snapshot else { return }
            guard snapshot.exists else {
                onChange(nil)
                return
            }
            onChange(try? snapshot.data(as: T.self))
        }
    }

    /// Wraps `addSnapshotListener`, decoding each changed document and
    /// reporting `.added`/`.modified` (with the decoded payload) or
    /// `.removed` (payload nil) per document change.
    static func listen<T: Decodable>(
        tripID: UUID,
        collection name: String,
        as type: T.Type,
        onChange: @escaping (DocumentChangeType, String, T?) -> Void
    ) -> ListenerRegistration {
        collection(tripID: tripID, name: name).addSnapshotListener { snapshot, _ in
            guard let snapshot else { return }
            for change in snapshot.documentChanges {
                let docID = change.document.documentID
                switch change.type {
                case .added, .modified:
                    onChange(change.type, docID, try? change.document.data(as: T.self))
                case .removed:
                    onChange(change.type, docID, nil)
                }
            }
        }
    }
}
