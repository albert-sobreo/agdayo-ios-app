import SwiftUI

enum TripSectionRoute: Hashable {
    case itinerary
    case accommodations
    case budget
    case preparation
    case transport
    case notes
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                NavigationLink(value: TripSectionRoute.itinerary) {
                    SquareNavCard(iconName: "map", subtitle: "\(activityCount) Activities", title: "Itinerary", accentColor: accentColor)
                }
                NavigationLink(value: TripSectionRoute.budget) {
                    SquareNavCard(iconName: "banknote", subtitle: budgetedTotal.formattedCurrency(code: currency), title: "Budget", accentColor: accentColor)
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
            }
            .padding(.horizontal)
            .padding(.vertical, 24)
        }
        .buttonStyle(.plain)
    }
}
