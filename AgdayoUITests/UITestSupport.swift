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

/// Firebase Auth persists a signed-in session in the Keychain, which
/// survives `-UITestReset` (that only clears UserDefaults/SwiftData) — a
/// real account signed in during manual testing stays signed in across
/// automated runs. Any test whose assertions depend on a signed-out,
/// no-synced-trips starting state must call this first, since a persisted
/// session pulls the account's real cloud trips into the fresh local store
/// via `RootTabView`'s member-trip sync as soon as the app launches.
@MainActor
func ensureSignedOut(_ app: XCUIApplication) {
    app.tabBars.buttons["Profile"].tap()
    let signOutButton = app.buttons["Sign Out"]
    if signOutButton.waitForExistence(timeout: 15) {
        signOutButton.tap()
    }
}
