import Foundation
import SwiftData
import Testing
@testable import Agdayo

@MainActor
struct MemberCostServiceTests {
    @Test func splitItemUsesItsSplitAndUnsplitItemIsSharedByEveryone() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        let dinner = Activity(title: "Dinner", cost: 200, paidByUID: "alice", splitUIDs: ["alice", "bob"], trip: trip)
        let tour = Activity(title: "Tour", cost: 300, trip: trip)
        context.insert(dinner)
        context.insert(tour)

        let costs = MemberCostService.breakdown(
            activities: [dinner, tour], accommodations: [], transportSegments: [], expenses: [],
            currency: "PHP", memberUIDs: ["alice", "bob", "carol"]
        )
        #expect(costs["alice"]?.activities == 200) // 100 of dinner + 100 of the tour
        #expect(costs["bob"]?.activities == 200)
        #expect(costs["carol"]?.activities == 100) // only the unsplit tour
        #expect(costs["alice"]?.paid == 200)
        #expect(costs["carol"]?.paid == 0)
    }

    @Test func contributionsListEachPersonsShareAndThePayer() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        let dinner = Activity(
            title: "Dinner", cost: 300, paidByUID: "bob",
            splitUIDs: ["alice", "bob"], splitAmounts: ["alice": 100, "bob": 200], trip: trip
        )
        context.insert(dinner)

        let rows = MemberCostService.contributions(
            .activities, activities: [dinner], accommodations: [], transportSegments: [], expenses: [],
            currency: "PHP", memberUIDs: ["alice", "bob"]
        )
        #expect(rows.count == 1)
        #expect(rows.first?.total == 300)
        #expect(rows.first?.paidByUID == "bob")
        #expect(rows.first?.shares == ["alice": 100, "bob": 200])
    }

    @Test func foreignCostWithoutRateHasNoTotalOrShares() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        let souvenir = Activity(title: "Souvenir", cost: 10, costCurrency: "USD", trip: trip)
        context.insert(souvenir)

        let rows = MemberCostService.contributions(
            .activities, activities: [souvenir], accommodations: [], transportSegments: [], expenses: [],
            currency: "PHP", memberUIDs: ["alice", "bob"]
        )
        #expect(rows.first?.total == nil)
        #expect(rows.first?.shares.isEmpty == true)
    }
}
