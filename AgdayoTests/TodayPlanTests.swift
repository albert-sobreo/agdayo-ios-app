import Foundation
import Testing
@testable import Agdayo

struct TodayPlanTests {
    private let calendar = Calendar.current

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let start = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start)!
    }

    private func activity(_ title: String, _ date: Date, pinned: Bool = true) -> Activity {
        Activity(title: title, latitude: pinned ? 16.41 : nil, longitude: pinned ? 120.59 : nil, date: date)
    }

    @Test func nextIsTheFirstStopNotYetStarted() {
        let plan = TodayPlan(
            activities: [activity("Lunch", at(0, 12)), activity("Coffee", at(0, 15)), activity("Dinner", at(0, 19))],
            stays: [],
            now: at(0, 13)
        )
        #expect(plan.next?.title == "Coffee")
        #expect(plan.laterToday.map(\.title) == ["Dinner"])
        #expect(plan.fallbackOrigin?.name == "Lunch")
        #expect(plan.nextIsTomorrowOrLater == false)
    }

    @Test func afterTheLastStopItShowsTomorrowsFirst() {
        let stay = Accommodation(name: "Hotel", latitude: 16.40, longitude: 120.60, startDate: at(-1, 0), endDate: at(2, 0))
        let plan = TodayPlan(
            activities: [activity("Dinner", at(0, 19)), activity("Breakfast", at(1, 8))],
            stays: [stay],
            now: at(0, 22)
        )
        #expect(plan.next?.title == "Breakfast")
        #expect(plan.nextIsTomorrowOrLater)
        #expect(plan.laterToday.isEmpty)
        // Nothing earlier that day, so travel starts from the stay.
        #expect(plan.fallbackOrigin?.name == "Hotel")
    }

    @Test func unpinnedPreviousStopIsSkipped() {
        let plan = TodayPlan(
            activities: [activity("Somewhere", at(0, 10), pinned: false), activity("Museum", at(0, 14))],
            stays: [],
            now: at(0, 11)
        )
        #expect(plan.fallbackOrigin == nil)
    }

    @Test func leaveText() {
        let now = at(0, 14)
        let soon = TodayPlan.leaveText(leaveBy: at(0, 14, 12), now: now)
        #expect(soon.text == "Leave in 12 min")
        #expect(!soon.isLate)
        #expect(TodayPlan.leaveText(leaveBy: now.addingTimeInterval(20), now: now).text == "Leave now")
        let late = TodayPlan.leaveText(leaveBy: at(0, 13, 52), now: now)
        #expect(late.text == "8 min late")
        #expect(late.isLate)
        #expect(TodayPlan.leaveText(leaveBy: at(0, 17), now: now).text.hasPrefix("Leave by"))
    }

    @Test func leaveByIncludesSpareTime() {
        let leave = TravelPlanning.leaveBy(arrival: at(0, 15), travelTime: 20 * 60, spare: TravelPlanning.leaveBySpare)
        #expect(leave == at(0, 14, 35))
    }
}
