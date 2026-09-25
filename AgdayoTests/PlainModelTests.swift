import Foundation
import SwiftData
import Testing
@testable import Agdayo

/// `BudgetCategory`, `Settlement`, `Accommodation`, `DayNote`, and
/// `PreparationTask` have no computed logic of their own beyond storing
/// fields and their `trip` relationship — these confirm construction and
/// relationship wiring rather than inventing behavior to test.
@MainActor
struct PlainModelTests {
    @Test func budgetCategoryIsWiredToItsTrip() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now)
        context.insert(trip)
        let category = BudgetCategory(name: "Food", amount: 300, trip: trip)
        context.insert(category)
        #expect(trip.budgetCategories.contains(where: { $0.id == category.id }))
    }

    @Test func settlementIsWiredToItsTrip() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now)
        context.insert(trip)
        let settlement = Settlement(fromUID: "a", toUID: "b", amount: 50, trip: trip)
        context.insert(settlement)
        #expect(trip.settlements.contains(where: { $0.id == settlement.id }))
    }

    @Test func accommodationIsWiredToItsTrip() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now)
        context.insert(trip)
        let accommodation = Accommodation(name: "Hotel", trip: trip)
        context.insert(accommodation)
        #expect(trip.accommodations.contains(where: { $0.id == accommodation.id }))
    }

    @Test func dayNoteIsWiredToItsTrip() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now)
        context.insert(trip)
        let note = DayNote(day: .now, title: "Day 1", trip: trip)
        context.insert(note)
        #expect(trip.dayNotes.contains(where: { $0.id == note.id }))
    }

    @Test func preparationTaskIsWiredToItsTrip() {
        let context = makeTestContext()
        let trip = Trip(name: "Trip", location: "X", startDate: .now, endDate: .now)
        context.insert(trip)
        let task = PreparationTask(name: "Passport", trip: trip)
        context.insert(task)
        #expect(trip.preparationTasks.contains(where: { $0.id == task.id }))
    }

    @Test func userProfileStoresItsFields() {
        let profile = UserProfile(fullName: "Jan", homeRegion: "NCR", hasTravelExperience: true, preferredVacationTypes: [.beaches, .mountains])
        #expect(profile.fullName == "Jan")
        #expect(profile.homeRegion == "NCR")
        #expect(profile.hasTravelExperience == true)
        #expect(profile.preferredVacationTypes == [.beaches, .mountains])
    }
}
