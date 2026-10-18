import CoreLocation
import Foundation
import Testing
@testable import Agdayo

struct PlanMyDayStepTests {
    @Test func everyPaceStartsWithBreakfastAndRunsInTimeOrder() {
        for pace in Pace.allCases {
            let steps = pace.steps
            #expect(steps.first?.kind == .breakfast)
            let minutes = steps.map { $0.hour * 60 + $0.minute }
            #expect(minutes == minutes.sorted())
            #expect(steps.contains { $0.kind == .lunch })
            #expect(steps.contains { $0.kind == .dinner })
        }
    }

    @Test func balancedMatchesTheAgreedFlow() {
        let steps = Pace.balanced.steps
        #expect(steps[0].kind == .breakfast && steps[0].hour == 8)
        #expect(steps[1].kind == .activity)
        #expect(steps[2].kind == .lunch)
    }

    @Test func activityKindsFollowInterestsWithAFallback() {
        let kinds = Interest.activityKinds(for: [.food, .shopping])
        #expect(kinds.contains(.foodMarket))
        #expect(kinds.contains(.store))
        #expect(!kinds.contains(.museum))
        #expect(Interest.activityKinds(for: []) == [.landmark, .museum, .park])
    }

    @Test func everyInterestOffersSomethingToDoAndTheNewOnesAreReal() {
        for interest in Interest.allCases {
            #expect(!interest.activityKinds.isEmpty)
        }
        #expect(Interest.activityKinds(for: [.wellness]).contains(.spa))
        #expect(Interest.activityKinds(for: [.adventure]).contains(.hiking))
        #expect(Interest.activityKinds(for: [.adventure]).contains(.waterSports))
        #expect(Interest.activityKinds(for: [.nightlife]).contains(.musicVenue))
        #expect(Interest.activityKinds(for: [.nature]).contains(.hiking))
        #expect(Interest.activityKinds(for: [.family]).contains(.recreation))
    }

    @Test func mealStepsOfferTheRightPlaces() {
        #expect(StepKind.breakfast.placeKinds(for: []).contains(.cafe))
        #expect(StepKind.dinner.placeKinds(for: []) == [.restaurant])
        #expect(StepKind.coffee.placeKinds(for: []).allSatisfy { $0 == .cafe || $0 == .bakery })
        #expect(StepKind.activity.placeKinds(for: [.nature]).contains(.park))
    }

    @Test func candidateKeysIgnoreCaseAndWhitespace() {
        #expect(Candidate.key("  Ayala Museum ") == Candidate.key("ayala museum"))
    }

    @Test func travelTimeHasAFloorAndGrowsWithDistance() {
        let a = CLLocationCoordinate2D(latitude: 14.55, longitude: 121.02)
        let near = CLLocationCoordinate2D(latitude: 14.5501, longitude: 121.02)
        let far = CLLocationCoordinate2D(latitude: 14.65, longitude: 121.02)
        #expect(PlanMyDayModel.travelMinutes(from: a, to: near) == 10)
        #expect(PlanMyDayModel.travelMinutes(from: a, to: far) > PlanMyDayModel.travelMinutes(from: a, to: near))
    }

    @Test func baseNameKeepsTheFirstPartOfAnAddress() {
        let base = PlanBase(name: "Makati, Philippines", coordinate: CLLocationCoordinate2D(latitude: 14.5, longitude: 121), reason: "")
        #expect(base.searchName == "Makati")
    }
}

struct PlanMyDaySpatialTests {
    private func place(_ name: String, lat: Double, lon: Double) -> Candidate {
        Candidate(name: name, kind: .restaurant, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
    }

    @Test func spreadInterleavesAcrossAreasInsteadOfPilingUpInOne() {
        // Three places in one spot, one in another: the far one must not be last.
        let places = [
            place("A1", lat: 14.55, lon: 121.02),
            place("A2", lat: 14.5501, lon: 121.0201),
            place("A3", lat: 14.5502, lon: 121.0202),
            place("B1", lat: 14.60, lon: 121.06),
        ]
        let order = PlanMyDayModel.spread(places).map(\.name)
        #expect(order.count == 4)
        #expect(order[0] == "A1")
        #expect(order[1] == "B1")
    }

    @Test func gridCoversTheRadiusInsteadOfAFewDots() {
        let center = CLLocationCoordinate2D(latitude: 14.5689, longitude: 121.0306)
        let grid = PlaceSearchService.gridPoints(around: center, radius: 10_000)
        #expect(grid.count > 5 && grid.count <= 24)
        #expect(grid.first.map { $0.center.latitude == center.latitude } == true)
        // Cells reach out into every direction, not just a ring.
        let latitudes = grid.map(\.center.latitude)
        #expect((latitudes.max() ?? 0) > center.latitude && (latitudes.min() ?? 0) < center.latitude)
        // Neighboring cells overlap, so nothing falls between them.
        #expect(grid.allSatisfy { $0.radius >= 2_000 })
    }
}

struct PlanMyDayRankingTests {
    private func place(_ name: String, prominence: Double, lat: Double = 14.55, lon: Double = 121.02) -> Candidate {
        Candidate(name: name, kind: .restaurant, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), prominence: prominence)
    }

    @Test func applesRankingOrderSurvivesTheSpreadStep() {
        let places = [
            place("Top", prominence: 1.0, lat: 14.55),
            place("Second", prominence: 0.9, lat: 14.55),
            place("Third", prominence: 0.7, lat: 14.55),
            place("Unranked far", prominence: 0, lat: 14.60, lon: 121.07),
        ]
        let order = PlanMyDayModel.spread(places).map(\.name)
        #expect(Array(order.prefix(3)) == ["Top", "Second", "Third"])
        #expect(order.last == "Unranked far")
    }

    @Test func streetsAndJunctionsAreNotPlaces() {
        #expect(PlaceSearchService.looksLikeARoad("Museum Drive"))
        #expect(PlaceSearchService.looksLikeARoad("Tordesillas Street Junction"))
        #expect(PlaceSearchService.looksLikeARoad("Ayala Legazpi Underpass"))
        #expect(!PlaceSearchService.looksLikeARoad("Ayala Museum"))
        #expect(!PlaceSearchService.looksLikeARoad("Greenbelt Park"))
    }

    @Test func rankedQueriesAlwaysNameTheCity() {
        for kind in PlaceKind.allCases {
            let queries = kind.rankedQueries(in: "Makati")
            #expect(!queries.isEmpty)
            #expect(queries.allSatisfy { $0.contains("Makati") })
        }
    }
}

struct NameLanguageTests {
    @Test func nonLatinScriptsAreAlwaysTranslated() {
        #expect(NameLanguage.sourceLanguage(for: "新宿御苑") != nil)
        #expect(NameLanguage.sourceLanguage(for: "서울숲") != nil)
        #expect(NameLanguage.sourceLanguage(for: "วัดพระแก้ว") != nil)
        #expect(NameLanguage.hasNonLatinLetters("カフェ"))
        #expect(!NameLanguage.hasNonLatinLetters("Café Rosé"))
    }

    @Test func englishNamesAndShortProperNounsAreLeftAlone() {
        #expect(NameLanguage.sourceLanguage(for: "Ayala Museum") == nil)
        #expect(NameLanguage.sourceLanguage(for: "Greenbelt Park") == nil)
        #expect(NameLanguage.sourceLanguage(for: "Toyo Eatery") == nil)
        #expect(NameLanguage.sourceLanguage(for: "X") == nil)
    }
}

struct CityKeyTests {
    @Test func spellingsOfOnePlaceShareAKey() {
        #expect(Candidate.cityKey("Shinjuku") == Candidate.cityKey("Shinjuku-Ku"))
        #expect(Candidate.cityKey("Shinjuku City") == Candidate.cityKey("Shinjuku"))
        #expect(Candidate.cityKey("中原区, 川崎市") == Candidate.cityKey("川崎市"))
        #expect(Candidate.cityKey("Kawasaki-Shi") == Candidate.cityKey("Kawasaki"))
        #expect(Candidate.cityKey("Makati City") == Candidate.cityKey("Makati"))
    }

    @Test func differentPlacesStayApart() {
        #expect(Candidate.cityKey("Shinjuku") != Candidate.cityKey("Shibuya"))
        #expect(Candidate.cityKey(nil) == "")
        #expect(Candidate.cityKey("") == "")
    }
}
