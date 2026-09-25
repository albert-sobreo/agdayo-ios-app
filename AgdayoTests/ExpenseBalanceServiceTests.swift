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
        context.insert(Activity(title: "Dinner", cost: 200, paidByUID: "alice", splitUIDs: ["alice", "bob"], trip: trip))

        let balances = ExpenseBalanceService.balances(for: trip)
        #expect(balances["alice"] == 100)
        #expect(balances["bob"] == -100)
    }

    @Test func customSplitAmountsOverrideEvenSplit() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        context.insert(Activity(
            title: "Dinner", cost: 300, paidByUID: "alice",
            splitUIDs: ["alice", "bob"], splitAmounts: ["alice": 100, "bob": 200],
            trip: trip
        ))

        let balances = ExpenseBalanceService.balances(for: trip)
        #expect(balances["alice"] == 200) // paid 300, owes back only their own 100 share
        #expect(balances["bob"] == -200)
    }

    @Test func foreignCurrencyCostConvertsBothAmountAndCustomShares() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        // 10 USD at a 56 rate -> 560 PHP; custom shares are entered in USD too, so they convert the same way.
        context.insert(Activity(
            title: "Souvenirs", cost: 10, costCurrency: "USD", exchangeRateToTripCurrency: 56,
            paidByUID: "alice", splitUIDs: ["alice", "bob"], splitAmounts: ["alice": 4, "bob": 6],
            trip: trip
        ))

        let balances = ExpenseBalanceService.balances(for: trip)
        #expect(balances["alice"] == 336) // paid 560, owed 224 (4 * 56) of it back
        #expect(balances["bob"] == -336)
    }

    @Test func itemsWithoutPayerOrSplitAreExcluded() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        context.insert(Activity(title: "No payer", cost: 100, splitUIDs: ["alice", "bob"], trip: trip))
        context.insert(Activity(title: "No split", cost: 100, paidByUID: "alice", trip: trip))

        #expect(ExpenseBalanceService.balances(for: trip).isEmpty)
    }

    @Test func recordedSettlementsNetAgainstRawBalances() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        context.insert(Activity(title: "Dinner", cost: 200, paidByUID: "alice", splitUIDs: ["alice", "bob"], trip: trip))
        context.insert(Settlement(fromUID: "bob", toUID: "alice", amount: 100, trip: trip))

        let balances = ExpenseBalanceService.balances(for: trip)
        #expect(balances["alice"] == 0)
        #expect(balances["bob"] == 0)
    }

    @Test func settlementsProduceMinimalPaymentsForThreePeople() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        // Alice pays 300 split evenly 3 ways: Bob and Carl each owe 100.
        context.insert(Activity(title: "Trip essentials", cost: 300, paidByUID: "alice", splitUIDs: ["alice", "bob", "carl"], trip: trip))

        let settlements = ExpenseBalanceService.settlements(for: trip)
        #expect(settlements.count == 2)
        #expect(settlements.allSatisfy { $0.toUID == "alice" && $0.fromUID != $0.toUID })
        #expect(settlements.reduce(0) { $0 + $1.amount } == 200)
    }

    @Test func accommodationsAlwaysCountInTripCurrency() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        context.insert(Accommodation(name: "Hotel", totalCost: 1000, paidByUID: "alice", splitUIDs: ["alice", "bob"], trip: trip))

        let balances = ExpenseBalanceService.balances(for: trip)
        #expect(balances["alice"] == 500)
        #expect(balances["bob"] == -500)
    }
}
