import Foundation
import Testing
@testable import Agdayo

@MainActor
struct AgdayoServerTests {
    @Test func decodesAConnectCode() throws {
        let json = #"{"code":"ABCD-2345","expiresInSeconds":600}"#
        let code = try JSONDecoder().decode(AgdayoServer.ConnectCode.self, from: Data(json.utf8))
        #expect(code.code == "ABCD-2345")
        #expect(code.expiresInSeconds == 600)
    }

    @Test func decodesAGuide() throws {
        let json = """
        {"guide":{"countryCode":"SG","title":"Singapore",
          "sections":[{"id":"money","title":"Money","items":[{"text":"Cards and contactless work almost everywhere.","source":"https://example.com"},{"text":"Hawker stalls may be cash only."}]}],
          "sources":[{"title":"Example","url":"https://example.com"}],
          "checkedAt":"2026-11-04T00:00:00.000Z","updatedAt":"2026-11-04T00:00:00.000Z"}}
        """
        struct Wrapper: Decodable { let guide: CountryGuide }
        let guide = try AgdayoServer.decoder.decode(Wrapper.self, from: Data(json.utf8)).guide
        #expect(guide.sections.first?.items.count == 2)
        #expect(guide.sections.first?.items.last?.source == nil)
        #expect(guide.sources.first?.title == "Example")
    }
}
