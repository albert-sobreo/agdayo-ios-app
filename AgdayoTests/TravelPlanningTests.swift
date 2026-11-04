import CoreLocation
import Foundation
import MapKit
import Testing
@testable import Agdayo

struct TravelPlanningTests {
    private let calendar = Calendar.current

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))!
    }

    private func stay(_ name: String, from start: Int, to end: Int, pinned: Bool = true) -> Accommodation {
        Accommodation(
            name: name,
            latitude: pinned ? 1.3 : nil,
            longitude: pinned ? 103.8 : nil,
            startDate: day(start),
            endDate: day(end)
        )
    }

    @Test func stayCoversItsNightsAndCheckOutMorning() {
        let hotel = stay("Hotel", from: 0, to: 2)
        #expect(TravelPlanning.stay(for: day(0), in: [hotel])?.name == "Hotel")
        #expect(TravelPlanning.stay(for: day(2), in: [hotel])?.name == "Hotel")
        #expect(TravelPlanning.stay(for: day(3), in: [hotel]) == nil)
    }

    @Test func onChangeoverDayTheStayYouCheckOutOfWins() {
        let first = stay("First", from: 0, to: 2)
        let second = stay("Second", from: 2, to: 4)
        #expect(TravelPlanning.stay(for: day(2), in: [second, first])?.name == "First")
    }

    @Test func staysWithoutAPinAreIgnored() {
        let unpinned = stay("Unpinned", from: 0, to: 2, pinned: false)
        #expect(TravelPlanning.stay(for: day(1), in: [unpinned]) == nil)
    }

    @Test func shortHopsStartOnWalkingLongerOnesOnTransit() {
        let origin = CLLocationCoordinate2D(latitude: 1.3000, longitude: 103.8000)
        let near = CLLocationCoordinate2D(latitude: 1.3040, longitude: 103.8000) // ~450 m
        let far = CLLocationCoordinate2D(latitude: 1.3300, longitude: 103.8000)  // ~3.3 km
        #expect(TravelPlanning.initialMode(from: origin, to: near) == .walking)
        #expect(TravelPlanning.initialMode(from: origin, to: far) == .transit)
    }

    @Test func transitFallsBackToDrivingAndThenStops() {
        #expect(TravelPlanning.fallbackMode(after: .transit) == .automobile)
        #expect(TravelPlanning.fallbackMode(after: .automobile) == nil)
        #expect(TravelPlanning.fallbackMode(after: .walking) == nil)
    }

    @Test func leaveByIsArrivalMinusTravelTime() {
        let arrival = day(0).addingTimeInterval(9.5 * 3600)
        let leave = TravelPlanning.leaveBy(arrival: arrival, travelTime: 18 * 60)
        #expect(arrival.timeIntervalSince(leave) == 18 * 60)
    }

    @Test func tightWhenTravelTakesLongerThanTheGap() {
        let first = day(0).addingTimeInterval(12.5 * 3600)
        let next = first.addingTimeInterval(15 * 60)
        #expect(TravelPlanning.isTight(previousStart: first, nextStart: next, travelTime: 25 * 60))
        #expect(!TravelPlanning.isTight(previousStart: first, nextStart: next, travelTime: 10 * 60))
    }

    @Test func googleMapsLinkCarriesBothEndsAndTheMode() throws {
        let url = try #require(TravelPlanning.googleMapsURL(
            from: CLLocationCoordinate2D(latitude: 1.2834, longitude: 103.8607),
            to: CLLocationCoordinate2D(latitude: 1.2816, longitude: 103.8636),
            mode: .transit
        ))
        #expect(url.absoluteString == "https://www.google.com/maps/dir/?api=1&origin=1.2834,103.8607&destination=1.2816,103.8636&travelmode=transit")
        #expect(MKDirectionsTransportType.cycling.googleTravelMode == "bicycling")
        #expect(MKDirectionsTransportType.automobile.googleTravelMode == "driving")
    }
}
