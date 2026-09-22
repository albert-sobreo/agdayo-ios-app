import SwiftUI
import SwiftData

struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Trips", systemImage: "suitcase.fill") {
                NavigationStack {
                    TripListView()
                }
            }
            Tab("Map", systemImage: "map.fill") {
                NavigationStack {
                    GlobalMapView()
                }
            }
            Tab("Profile", systemImage: "person.crop.circle") {
                NavigationStack {
                    ProfileView()
                }
            }
        }
        .tint(.appPrimary)
        .fontDesign(.rounded)
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Trip.self, inMemory: true)
}
