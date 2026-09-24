import SwiftUI

enum TripSectionRoute: Hashable {
    case itinerary
    case accommodations
    case budget
    case balances
    case preparation
    case transport
    case notes
    case members
}

struct TripSectionsRow: View {
    let accentColor: Color
    let activityCount: Int
    let accommodationCount: Int
    let budgetedTotal: Double
    let overallBudget: Double
    let currency: String
    let taskCount: Int
    let transportCount: Int
    let noteCount: Int
    var memberCount: Int = 1
    var showsBalances: Bool = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                NavigationLink(value: TripSectionRoute.itinerary) {
                    SquareNavCard(iconName: "map", subtitle: "\(activityCount) Activities", title: "Itinerary", accentColor: accentColor)
                }
                NavigationLink(value: TripSectionRoute.budget) {
                    SquareNavCard(iconName: "banknote", subtitle: budgetedTotal.formattedCurrency(code: currency), title: "Budget", accentColor: accentColor)
                }
                if showsBalances {
                    NavigationLink(value: TripSectionRoute.balances) {
                        SquareNavCard(iconName: "arrow.left.arrow.right", subtitle: "Settle Up", title: "Balances", accentColor: accentColor)
                    }
                }
                NavigationLink(value: TripSectionRoute.accommodations) {
                    SquareNavCard(iconName: "bed.double", subtitle: "\(accommodationCount) Stays", title: "Accommodations", accentColor: accentColor)
                }
                NavigationLink(value: TripSectionRoute.preparation) {
                    SquareNavCard(iconName: "checklist", subtitle: "\(taskCount) Tasks", title: "Preparation", accentColor: accentColor)
                }
                NavigationLink(value: TripSectionRoute.transport) {
                    SquareNavCard(iconName: "airplane", subtitle: "\(transportCount) Segments", title: "Transport", accentColor: accentColor)
                }
                NavigationLink(value: TripSectionRoute.notes) {
                    SquareNavCard(iconName: "note.text", subtitle: "\(noteCount) Notes", title: "Day Notes", accentColor: accentColor)
                }
                NavigationLink(value: TripSectionRoute.members) {
                    SquareNavCard(iconName: "person.2", subtitle: "\(memberCount) Member\(memberCount == 1 ? "" : "s")", title: "Members", accentColor: accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
        }
        .buttonStyle(.plain)
    }
}
