import Foundation
import Testing
@testable import Agdayo

@MainActor
struct AgdayoServerTests {
    @Test func decodesTheWorkersRouteShape() throws {
        let json = """
        {"route":{"mode":"transit","durationSeconds":1320,"distanceMeters":6400,
          "fare":{"currency":"SGD","amount":1.59,"text":"S$1.59"},
          "steps":[
            {"kind":"walk","durationSeconds":240,"distanceMeters":300,"instruction":"Walk to Bayfront"},
            {"kind":"transit","durationSeconds":600,"distanceMeters":5800,
             "transit":{"lineName":"Downtown Line","lineShortName":"DT","vehicle":"Subway","color":"#005EC4",
                        "headsign":"Expo","departureStop":"Bayfront","arrivalStop":"Bugis",
                        "departureTime":"2026-12-10T01:17:00Z","arrivalTime":"2026-12-10T01:27:00.123456789Z","stopCount":4}}
          ],
          "timeAdjusted":false,"source":"Google","fetchedAt":"2026-11-04T12:00:00.000Z"}}
        """
        struct Wrapper: Decodable { let route: ServerRoute? }
        let route = try #require(try AgdayoServer.decoder.decode(Wrapper.self, from: Data(json.utf8)).route)
        #expect(route.steps.count == 2)
        #expect(route.steps[1].transit?.lineShortName == "DT")
        #expect(route.steps[1].transit?.stopCount == 4)
        #expect(route.firstDeparture == AgdayoServer.parseDate("2026-12-10T01:17:00Z"))
        #expect(route.steps[1].transit?.arrivalTime != nil)
        #expect(route.fare?.text == "S$1.59")
    }

    @Test func noRouteDecodesAsNil() throws {
        struct Wrapper: Decodable { let route: ServerRoute? }
        let wrapper = try AgdayoServer.decoder.decode(Wrapper.self, from: Data(#"{"route":null}"#.utf8))
        #expect(wrapper.route == nil)
    }
}
