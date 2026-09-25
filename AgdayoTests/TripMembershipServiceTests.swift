import Testing
@testable import Agdayo

/// Only the two pure helpers — every other `TripMembershipService` method
/// hits Firestore directly with no injectable seam, see the plan/README
/// note in this target for why those are out of scope.
struct TripMembershipServiceTests {
    @Test func extractJoinCodeTrimsAndUppercasesPlainCode() {
        #expect(TripMembershipService.extractJoinCode(from: "  abc123  ") == "ABC123")
    }

    @Test func extractJoinCodeParsesCodeFromJoinURL() {
        #expect(TripMembershipService.extractJoinCode(from: "agdayo://join?code=xyz789") == "XYZ789")
    }

    @Test func extractJoinCodeParsesCodeFromHTTPURLWithOtherQueryItems() {
        #expect(TripMembershipService.extractJoinCode(from: "https://agdayo.app/join?ref=abc&code=qwe456") == "QWE456")
    }

    @Test func generateRandomCodeHasRequestedLengthAndCharset() {
        let allowed = Set("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        let code = TripMembershipService.generateRandomCode(length: 8)
        #expect(code.count == 8)
        #expect(code.allSatisfy { allowed.contains($0) })
    }

    @Test func generateRandomCodeDefaultLengthIsSix() {
        #expect(TripMembershipService.generateRandomCode().count == 6)
    }
}
