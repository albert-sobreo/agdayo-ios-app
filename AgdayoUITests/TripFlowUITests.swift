import XCTest

/// Exercises create-trip -> trip-detail section navigation -> add-activity
/// as one continuous flow. Each launch (`-UITestReset`) starts from an empty
/// store, so splitting this into separate test methods would just repeat the
/// one genuinely network-dependent step (live MapKit location autocomplete)
/// multiple times for no added coverage.
final class TripFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCreateTripThenNavigateEverySectionAndAddAnActivity() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestReset"]
        app.launch()
        completeOnboarding(app)

        let tripName = "UI Test Trip"
        createTrip(app, name: tripName)
        openTripDetail(app, tripName: tripName)
        navigateEveryOtherSection(app)
        addActivity(app, title: "Museum Visit")
    }

    private func createTrip(_ app: XCUIApplication, name: String) {
        app.tabBars.buttons["Trips"].tap()

        let createButton = app.buttons["Create a Trip"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 25))
        createButton.tap()

        // Destination step — types into the live MapKit autocomplete field
        // and waits for a real network result. Result rows are dynamic
        // text, so they're tagged with a dedicated accessibility identifier
        // (see ManualTripFormView.swift) rather than matched by title.
        let searchField = app.textFields["Search destinations"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 25))
        searchField.tap()
        searchField.typeText("Manila")

        let firstResult = app.buttons.matching(identifier: "destinationSearchResult").firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 30), "Expected a live location search result for 'Manila'")
        firstResult.tap()

        // Date step — two ascending days, tagged with a dedicated
        // accessibility identifier (see TripDateRangeCalendar.swift) keyed
        // by calendar date, so the tap target is exact regardless of which
        // month is currently scrolled into view.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let startDate = calendar.date(byAdding: .day, value: 1, to: today)!
        let endDate = calendar.date(byAdding: .day, value: 3, to: today)!

        let startDayButton = app.buttons[calendarDayIdentifier(for: startDate, calendar: calendar)]
        XCTAssertTrue(startDayButton.waitForExistence(timeout: 25))
        startDayButton.tap()
        app.buttons[calendarDayIdentifier(for: endDate, calendar: calendar)].tap()
        app.buttons["Next"].tap()

        // Details step.
        let nameField = app.textFields["Trip Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 25))
        nameField.tap()
        nameField.typeText(name)

        app.buttons["Create Trip"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 25))
    }

    private func openTripDetail(_ app: XCUIApplication, tripName: String) {
        app.staticTexts[tripName].tap()
        XCTAssertTrue(app.staticTexts["Activities"].waitForExistence(timeout: 25))
    }

    /// Every `TripSectionsRow` card except Itinerary, which stays inline on
    /// `TripDetailView` itself — used below by `addActivity` instead.
    private func navigateEveryOtherSection(_ app: XCUIApplication) {
        for section in ["Budget", "Accommodations", "Preparation", "Transport", "Day Notes", "Members"] {
            let card = app.staticTexts[section]
            XCTAssertTrue(card.waitForExistence(timeout: 25), "\(section) section card should be visible")
            card.tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 25), "\(section) destination should load")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.staticTexts["Activities"].waitForExistence(timeout: 25), "should return to TripDetailView after \(section)")
        }
    }

    private func addActivity(_ app: XCUIApplication, title: String) {
        // With no activities yet, ItineraryTimelineView shows both its own
        // EmptyStateView "Add Activity" button (inside the ScrollView) and
        // the toolbar's — which on this OS is a Menu (AI generation is
        // available), not a plain button, so tapping it would just open a
        // menu instead of the sheet. Target the ScrollView one specifically.
        let addButton = app.scrollViews.buttons["Add Activity"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 25))
        addButton.tap()

        let titleField = app.textFields["Title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 25))
        titleField.tap()
        titleField.typeText(title)

        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 25))
    }

    private func calendarDayIdentifier(for date: Date, calendar: Calendar) -> String {
        "calendarDay-\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))-\(calendar.component(.day, from: date))"
    }
}
