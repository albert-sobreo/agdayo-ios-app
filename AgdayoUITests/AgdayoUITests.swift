import XCTest

final class AgdayoUITests: XCTestCase {
    override func setUpWithError() throws {
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
    }

    @MainActor
    func testOnboardingLeadsToTabBar() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launch()

        completeOnboarding(app)
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testTabBarNavigationSwitchesRootViews() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launch()
        completeOnboarding(app)

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

        for tabName in ["Trips", "Map", "Profile", "Home"] {
            let tab = tabBar.buttons[tabName]
            XCTAssertTrue(tab.exists, "\(tabName) tab should exist")
            tab.tap()
        }
    }

    @MainActor
    func testProfileTabShowsSignInEntryPoint() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launch()
        completeOnboarding(app)

        app.tabBars.buttons["Profile"].tap()

        // Firebase Auth persists a signed-in session in the Keychain, which
        // survives `-UITestReset` (that only clears UserDefaults/SwiftData).
        // If a prior session is still signed in, sign out first so the
        // entry point is reachable regardless of the device's starting state.
        let signOutButton = app.buttons["Sign Out"]
        if signOutButton.waitForExistence(timeout: 15) {
            signOutButton.tap()
        }

        // The button's label combines "Sign In" with a trailing chevron
        // image, so it isn't an exact accessibility label match.
        let signInButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Sign In'")).firstMatch
        XCTAssertTrue(signInButton.waitForExistence(timeout: 15))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
