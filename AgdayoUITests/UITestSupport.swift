import XCTest

/// Taps through the 3-page onboarding flow shown on a clean `-UITestReset`
/// launch, landing on `RootTabView`.
@MainActor
func completeOnboarding(_ app: XCUIApplication) {
    for _ in 0..<5 {
        if app.buttons["Get Started"].waitForExistence(timeout: 5) {
            app.buttons["Get Started"].tap()
            return
        }
        if app.buttons["Next"].waitForExistence(timeout: 5) {
            app.buttons["Next"].tap()
        }
    }
}
