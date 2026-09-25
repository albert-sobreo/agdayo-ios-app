import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import Agdayo

@MainActor
struct TripTests {
    @Test func statusReflectsUpcomingActiveAndCompletedDates() {
        let context = makeTestContext()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        let upcoming = Trip(name: "Upcoming", location: "X", startDate: calendar.date(byAdding: .day, value: 1, to: today)!, endDate: calendar.date(byAdding: .day, value: 3, to: today)!)
        context.insert(upcoming)
        #expect(upcoming.status == .upcoming)

        let active = Trip(name: "Active", location: "X", startDate: calendar.date(byAdding: .day, value: -1, to: today)!, endDate: calendar.date(byAdding: .day, value: 1, to: today)!)
        context.insert(active)
        #expect(active.status == .active)

        let completed = Trip(name: "Completed", location: "X", startDate: calendar.date(byAdding: .day, value: -3, to: today)!, endDate: calendar.date(byAdding: .day, value: -1, to: today)!)
        context.insert(completed)
        #expect(completed.status == .completed)
    }

    @Test func numberOfDaysIsInclusiveAndAtLeastOne() {
        let context = makeTestContext()
        let start = Date(timeIntervalSince1970: 0)
        let fourDaysLater = Calendar.current.date(byAdding: .day, value: 4, to: start)!

        let multiDay = Trip(name: "Multi", location: "X", startDate: start, endDate: fourDaysLater)
        context.insert(multiDay)
        #expect(multiDay.numberOfDays == 5)

        let sameDay = Trip(name: "Single", location: "X", startDate: start, endDate: start)
        context.insert(sameDay)
        #expect(sameDay.numberOfDays == 1)
    }

    @Test func coordinateRequiresBothLatitudeAndLongitude() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, latitude: 14.5)
        context.insert(trip)
        #expect(trip.coordinate == nil)

        trip.longitude = 121.0
        #expect(trip.coordinate?.latitude == 14.5)
        #expect(trip.coordinate?.longitude == 121.0)
    }

    @Test func costTotalsSumAcrossActivitiesAccommodationsAndTransport() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)

        context.insert(BudgetCategory(name: "Misc", amount: 500, trip: trip))
        context.insert(Activity(title: "Museum", cost: 200, trip: trip))
        context.insert(Accommodation(name: "Hotel", totalCost: 1000, trip: trip))
        context.insert(TransportSegment(cost: 300, currency: "PHP", trip: trip))

        #expect(trip.activityCostsTotal == 200)
        #expect(trip.accommodationCostsTotal == 1000)
        #expect(trip.transportCostsTotal == 300)
        #expect(trip.budgetedTotal == 2000)
    }

    @Test func activityCostsExcludeUnconvertedForeignCurrency() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, currency: "PHP")
        context.insert(trip)
        // No exchangeRateToTripCurrency captured for this foreign-currency cost.
        context.insert(Activity(title: "Foreign", cost: 100, costCurrency: "USD", trip: trip))
        #expect(trip.activityCostsTotal == 0)
    }

    @Test func isOverBudgetOnlyWhenBudgetIsSetAndExceeded() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now, overallBudget: 0)
        context.insert(trip)
        context.insert(Accommodation(name: "Hotel", totalCost: 9999, trip: trip))
        #expect(trip.isOverBudget == false)

        trip.overallBudget = 100
        #expect(trip.isOverBudget == true)

        trip.overallBudget = 100_000
        #expect(trip.isOverBudget == false)
    }

    @Test func planningProgressCountsNonEmptySections() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now)
        context.insert(trip)
        #expect(trip.planningProgress.total == 5)
        #expect(trip.planningProgress.completed == 0)

        context.insert(Activity(title: "A", trip: trip))
        context.insert(BudgetCategory(name: "B", trip: trip))
        #expect(trip.planningProgress.completed == 2)
    }
}
