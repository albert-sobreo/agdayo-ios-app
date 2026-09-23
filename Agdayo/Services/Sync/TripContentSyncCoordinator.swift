import FirebaseFirestore
import Observation
import SwiftData

struct TripMemberDTO: Codable {
    var uid: String
    var role: String
}

struct TripFieldsDTO: Codable {
    var ownerUID: String?
    var name: String
    var location: String
    var theme: String
    var startDate: Date
    var endDate: Date
    var overallBudget: Double
    var currency: String
    var tripDescription: String
    var joinCode: String?
    var latitude: Double?
    var longitude: Double?
}

struct TripMemberRecord: Identifiable {
    var id: String { profile.uid }
    let profile: AppUserProfile
    let role: String
    var isOwner: Bool { role.lowercased() == "owner" }
}

/// Attaches Firestore realtime listeners for one open, shared trip — the
/// trip document's own fields, its 6 content subcollections, and `members`
/// — and keeps local SwiftData objects in sync while it's running.
/// Started/stopped by `TripDetailView`'s lifecycle; does nothing for solo
/// (unshared) trips.
@Observable
@MainActor
final class TripContentSyncCoordinator {
    private(set) var memberProfiles: [AppUserProfile] = []
    private(set) var memberRoles: [String: String] = [:]
    private(set) var currentJoinCode: String?

    private var listeners: [ListenerRegistration] = []

    var memberRecords: [TripMemberRecord] {
        memberProfiles.map { profile in
            TripMemberRecord(
                profile: profile,
                role: memberRoles[profile.uid] ?? "member"
            )
        }
    }

    func start(for trip: Trip, modelContext: ModelContext) {
        stop()
        let tripID = trip.id

        listeners.append(FirestoreCollectionSync.listen(tripID: tripID, collection: "activities", as: ActivityDTO.self) { [weak self] type, docID, dto in
            Task { @MainActor in self?.applyActivity(type: type, docID: docID, dto: dto, trip: trip, modelContext: modelContext) }
        })
        listeners.append(FirestoreCollectionSync.listen(tripID: tripID, collection: "accommodations", as: AccommodationDTO.self) { [weak self] type, docID, dto in
            Task { @MainActor in self?.applyAccommodation(type: type, docID: docID, dto: dto, trip: trip, modelContext: modelContext) }
        })
        listeners.append(FirestoreCollectionSync.listen(tripID: tripID, collection: "budgetCategories", as: BudgetCategoryDTO.self) { [weak self] type, docID, dto in
            Task { @MainActor in self?.applyBudgetCategory(type: type, docID: docID, dto: dto, trip: trip, modelContext: modelContext) }
        })
        listeners.append(FirestoreCollectionSync.listen(tripID: tripID, collection: "preparationTasks", as: PreparationTaskDTO.self) { [weak self] type, docID, dto in
            Task { @MainActor in self?.applyPreparationTask(type: type, docID: docID, dto: dto, trip: trip, modelContext: modelContext) }
        })
        listeners.append(FirestoreCollectionSync.listen(tripID: tripID, collection: "transportSegments", as: TransportSegmentDTO.self) { [weak self] type, docID, dto in
            Task { @MainActor in self?.applyTransportSegment(type: type, docID: docID, dto: dto, trip: trip, modelContext: modelContext) }
        })
        listeners.append(FirestoreCollectionSync.listen(tripID: tripID, collection: "dayNotes", as: DayNoteDTO.self) { [weak self] type, docID, dto in
            Task { @MainActor in self?.applyDayNote(type: type, docID: docID, dto: dto, trip: trip, modelContext: modelContext) }
        })

        // Listen for members subcollection changes
        listeners.append(FirestoreCollectionSync.listen(tripID: tripID, collection: "members", as: TripMemberDTO.self) { [weak self] type, docID, dto in
            Task { @MainActor in await self?.applyMember(type: type, docID: docID, dto: dto) }
        })

        listeners.append(FirestoreCollectionSync.listenTripDocument(tripID: tripID, as: TripFieldsDTO.self) { [weak self] dto in
            Task { @MainActor in self?.applyTripFields(dto, trip: trip, modelContext: modelContext) }
        })
    }

    func stop() {
        listeners.forEach { $0.remove() }
        listeners.removeAll()
        memberProfiles.removeAll()
        memberRoles.removeAll()
        currentJoinCode = nil
    }

    private func applyActivity(type: DocumentChangeType, docID: String, dto: ActivityDTO?, trip: Trip, modelContext: ModelContext) {
        guard let id = UUID(uuidString: docID) else { return }
        switch type {
        case .added, .modified:
            guard let dto else { return }
            if let existing = trip.activities.first(where: { $0.id == id }) {
                existing.apply(dto)
            } else {
                modelContext.insert(Activity(id: id, dto: dto, trip: trip))
            }
        case .removed:
            if let existing = trip.activities.first(where: { $0.id == id }) {
                modelContext.delete(existing)
            }
        }
    }

    private func applyAccommodation(type: DocumentChangeType, docID: String, dto: AccommodationDTO?, trip: Trip, modelContext: ModelContext) {
        guard let id = UUID(uuidString: docID) else { return }
        switch type {
        case .added, .modified:
            guard let dto else { return }
            if let existing = trip.accommodations.first(where: { $0.id == id }) {
                existing.apply(dto)
            } else {
                modelContext.insert(Accommodation(id: id, dto: dto, trip: trip))
            }
        case .removed:
            if let existing = trip.accommodations.first(where: { $0.id == id }) {
                modelContext.delete(existing)
            }
        }
    }

    private func applyBudgetCategory(type: DocumentChangeType, docID: String, dto: BudgetCategoryDTO?, trip: Trip, modelContext: ModelContext) {
        guard let id = UUID(uuidString: docID) else { return }
        switch type {
        case .added, .modified:
            guard let dto else { return }
            if let existing = trip.budgetCategories.first(where: { $0.id == id }) {
                existing.apply(dto)
            } else {
                modelContext.insert(BudgetCategory(id: id, dto: dto, trip: trip))
            }
        case .removed:
            if let existing = trip.budgetCategories.first(where: { $0.id == id }) {
                modelContext.delete(existing)
            }
        }
    }

    private func applyPreparationTask(type: DocumentChangeType, docID: String, dto: PreparationTaskDTO?, trip: Trip, modelContext: ModelContext) {
        guard let id = UUID(uuidString: docID) else { return }
        switch type {
        case .added, .modified:
            guard let dto else { return }
            if let existing = trip.preparationTasks.first(where: { $0.id == id }) {
                existing.apply(dto)
            } else {
                modelContext.insert(PreparationTask(id: id, dto: dto, trip: trip))
            }
        case .removed:
            if let existing = trip.preparationTasks.first(where: { $0.id == id }) {
                modelContext.delete(existing)
            }
        }
    }

    private func applyTransportSegment(type: DocumentChangeType, docID: String, dto: TransportSegmentDTO?, trip: Trip, modelContext: ModelContext) {
        guard let id = UUID(uuidString: docID) else { return }
        switch type {
        case .added, .modified:
            guard let dto else { return }
            if let existing = trip.transportSegments.first(where: { $0.id == id }) {
                existing.apply(dto)
            } else {
                modelContext.insert(TransportSegment(id: id, dto: dto, trip: trip))
            }
        case .removed:
            if let existing = trip.transportSegments.first(where: { $0.id == id }) {
                modelContext.delete(existing)
            }
        }
    }

    private func applyDayNote(type: DocumentChangeType, docID: String, dto: DayNoteDTO?, trip: Trip, modelContext: ModelContext) {
        guard let id = UUID(uuidString: docID) else { return }
        switch type {
        case .added, .modified:
            guard let dto else { return }
            if let existing = trip.dayNotes.first(where: { $0.id == id }) {
                existing.apply(dto)
            } else {
                modelContext.insert(DayNote(id: id, dto: dto, trip: trip))
            }
        case .removed:
            if let existing = trip.dayNotes.first(where: { $0.id == id }) {
                modelContext.delete(existing)
            }
        }
    }

    private func applyMember(type: DocumentChangeType, docID: String, dto: TripMemberDTO?) async {
        switch type {
        case .added, .modified:
            guard let dto else { return }
            memberRoles[dto.uid] = dto.role
            if let profile = try? await UserDirectoryService.fetchProfile(uid: dto.uid) {
                if let idx = memberProfiles.firstIndex(where: { $0.uid == dto.uid }) {
                    memberProfiles[idx] = profile
                } else {
                    memberProfiles.append(profile)
                }
            }
        case .removed:
            memberRoles.removeValue(forKey: docID)
            memberProfiles.removeAll { $0.uid == docID }
        }
    }

    /// `dto == nil` means the trip document itself was deleted remotely
    /// (e.g. the owner deleted it from another device) — remove the local
    /// mirror too rather than leaving a dangling trip behind.
    private func applyTripFields(_ dto: TripFieldsDTO?, trip: Trip, modelContext: ModelContext) {
        guard let dto else {
            modelContext.delete(trip)
            return
        }
        currentJoinCode = dto.joinCode
        trip.name = dto.name
        trip.location = dto.location
        trip.theme = TripTheme(rawValue: dto.theme) ?? trip.theme
        trip.startDate = dto.startDate
        trip.endDate = dto.endDate
        trip.overallBudget = dto.overallBudget
        trip.currency = dto.currency
        trip.tripDescription = dto.tripDescription
        if let latitude = dto.latitude { trip.latitude = latitude }
        if let longitude = dto.longitude { trip.longitude = longitude }
    }
}
