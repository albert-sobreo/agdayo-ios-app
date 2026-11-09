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

    @Test func legsJoinConsecutiveActivities() {
        let kinds: [TravelPlanning.TimelineRowKind] = [.activity, .activity]
        #expect(TravelPlanning.legOriginIndex(before: 0, in: kinds) == nil)
        #expect(TravelPlanning.legOriginIndex(before: 1, in: kinds) == 0)
    }

    @Test func legsLookPastCheckInAndCheckOut() {
        // Lunch, check-in, dinner: dinner's leg starts at lunch, not the stay.
        let kinds: [TravelPlanning.TimelineRowKind] = [.activity, .stay, .activity]
        #expect(TravelPlanning.legOriginIndex(before: 2, in: kinds) == 0)
        // The check-in row itself never gets a leg.
        #expect(TravelPlanning.legOriginIndex(before: 1, in: kinds) == nil)
    }

    @Test func noLegFromAStayOrAcrossTransport() {
        // Check-out first thing, then breakfast: no leg from the stay.
        #expect(TravelPlanning.legOriginIndex(before: 1, in: [.stay, .activity]) == nil)
        // Landing (or a van ride) between two activities: no leg across it.
        #expect(TravelPlanning.legOriginIndex(before: 2, in: [.activity, .transport, .activity]) == nil)
        #expect(TravelPlanning.legOriginIndex(before: 1, in: [.transport, .activity]) == nil)
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
