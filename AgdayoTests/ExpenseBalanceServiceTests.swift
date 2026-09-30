import Foundation
import SwiftData
import Testing
@testable import Agdayo

@MainActor
struct ExpenseBalanceServiceTests {
    @Test func evenSplitCreditsPayerAndDebitsOthers() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        let activity = Activity(title: "Dinner", cost: 200, paidByUID: "alice", splitUIDs: ["alice", "bob"], trip: trip)
        context.insert(activity)

        let balances = ExpenseBalanceService.balances(activities: [activity], accommodations: [], transportSegments: [], recordedSettlements: [], currency: "PHP")
        #expect(balances["alice"] == 100)
        #expect(balances["bob"] == -100)
    }

    @Test func customSplitAmountsOverrideEvenSplit() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        let activity = Activity(
            title: "Dinner", cost: 300, paidByUID: "alice",
            splitUIDs: ["alice", "bob"], splitAmounts: ["alice": 100, "bob": 200],
            trip: trip
        )
        context.insert(activity)

        let balances = ExpenseBalanceService.balances(activities: [activity], accommodations: [], transportSegments: [], recordedSettlements: [], currency: "PHP")
        #expect(balances["alice"] == 200) // paid 300, owes back only their own 100 share
        #expect(balances["bob"] == -200)
    }

    @Test func foreignCurrencyCostConvertsBothAmountAndCustomShares() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        // 10 USD at a 56 rate -> 560 PHP; custom shares are entered in USD too, so they convert the same way.
        let activity = Activity(
            title: "Souvenirs", cost: 10, costCurrency: "USD", exchangeRateToTripCurrency: 56,
            paidByUID: "alice", splitUIDs: ["alice", "bob"], splitAmounts: ["alice": 4, "bob": 6],
            trip: trip
        )
        context.insert(activity)

        let balances = ExpenseBalanceService.balances(activities: [activity], accommodations: [], transportSegments: [], recordedSettlements: [], currency: "PHP")
        #expect(balances["alice"] == 336) // paid 560, owed 224 (4 * 56) of it back
        #expect(balances["bob"] == -336)
    }

    @Test func itemsWithoutPayerOrSplitAreExcluded() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        let noPayer = Activity(title: "No payer", cost: 100, splitUIDs: ["alice", "bob"], trip: trip)
        let noSplit = Activity(title: "No split", cost: 100, paidByUID: "alice", trip: trip)
        context.insert(noPayer)
        context.insert(noSplit)

        #expect(ExpenseBalanceService.balances(activities: [noPayer, noSplit], accommodations: [], transportSegments: [], recordedSettlements: [], currency: "PHP").isEmpty)
    }

    @Test func recordedSettlementsNetAgainstRawBalances() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        let activity = Activity(title: "Dinner", cost: 200, paidByUID: "alice", splitUIDs: ["alice", "bob"], trip: trip)
        let settlement = Settlement(fromUID: "bob", toUID: "alice", amount: 100, trip: trip)
        context.insert(activity)
        context.insert(settlement)

        let balances = ExpenseBalanceService.balances(activities: [activity], accommodations: [], transportSegments: [], recordedSettlements: [settlement], currency: "PHP")
        #expect(balances["alice"] == 0)
        #expect(balances["bob"] == 0)
    }

    @Test func settlementsProduceMinimalPaymentsForThreePeople() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        // Alice pays 300 split evenly 3 ways: Bob and Carl each owe 100.
        let activity = Activity(title: "Trip essentials", cost: 300, paidByUID: "alice", splitUIDs: ["alice", "bob", "carl"], trip: trip)
        context.insert(activity)

        let settlements = ExpenseBalanceService.settlements(activities: [activity], accommodations: [], transportSegments: [], recordedSettlements: [], currency: "PHP")
        #expect(settlements.count == 2)
        #expect(settlements.allSatisfy { $0.toUID == "alice" && $0.fromUID != $0.toUID })
        #expect(settlements.reduce(0) { $0 + $1.amount } == 200)
    }

    @Test func accommodationsAlwaysCountInTripCurrency() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        let accommodation = Accommodation(name: "Hotel", totalCost: 1000, paidByUID: "alice", splitUIDs: ["alice", "bob"], trip: trip)
        context.insert(accommodation)

        let balances = ExpenseBalanceService.balances(activities: [], accommodations: [accommodation], transportSegments: [], recordedSettlements: [], currency: "PHP")
        #expect(balances["alice"] == 500)
        #expect(balances["bob"] == -500)
    }
}
