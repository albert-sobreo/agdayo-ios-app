import Foundation
import SwiftData
import CoreLocation

enum PollKind: String, Codable {
    /// A free-form question with its own options ("Which beach?").
    case question
    /// A single proposed activity the group votes Yes/No on.
    case activityProposal
}

@Model
final class TripPoll {
    @Attribute(.unique) var id: UUID
    var kind: PollKind
    /// The question, or the proposed activity's title.
    var question: String
    /// Fixed once created — votes refer to an option by its index here.
    var options: [String]
    /// Option index chosen by each voter, keyed by uid. One vote per member.
    var votes: [String: Int] = [:]
    var createdByUID: String
    var createdAt: Date
    /// The owner closes a vote; a closed vote shows its result and takes no more votes.
    var isClosed: Bool

    // Only used by `.activityProposal`, to build the `Activity` on approval.
    var location: String
    var latitude: Double?
    var longitude: Double?
    var iconName: String
    var proposedDate: Date?

    var trip: Trip?

    init(
        id: UUID = UUID(),
        kind: PollKind,
        question: String,
        options: [String],
        votes: [String: Int] = [:],
        createdByUID: String,
        createdAt: Date = .now,
        isClosed: Bool = false,
        location: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        iconName: String = "mappin.and.ellipse",
        proposedDate: Date? = nil,
        trip: Trip? = nil
    ) {
        self.id = id
        self.kind = kind
        self.question = question
        self.options = options
        self.votes = votes
        self.createdByUID = createdByUID
        self.createdAt = createdAt
        self.isClosed = isClosed
        self.location = location
        self.latitude = latitude
        self.longitude = longitude
        self.iconName = iconName
        self.proposedDate = proposedDate
        self.trip = trip
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Votes that count: only those from `eligible` voters (the trip's current
    /// members), so someone who left doesn't skew the tally. `nil` when the
    /// member list isn't known (unshared trip, or still loading) counts every vote.
    private func countedVotes(among eligible: Set<String>?) -> [String: Int] {
        guard let eligible else { return votes }
        return votes.filter { eligible.contains($0.key) }
    }

    func totalVotes(among eligible: Set<String>? = nil) -> Int {
        countedVotes(among: eligible).count
    }

    func voteCount(for optionIndex: Int, among eligible: Set<String>? = nil) -> Int {
        countedVotes(among: eligible).values.filter { $0 == optionIndex }.count
    }

    /// Options with the most votes — more than one on a tie, none before any vote.
    func leadingOptionIndices(among eligible: Set<String>? = nil) -> [Int] {
        let counts = options.indices.map { voteCount(for: $0, among: eligible) }
        guard let top = counts.max(), top > 0 else { return [] }
        return options.indices.filter { counts[$0] == top }
    }
}
