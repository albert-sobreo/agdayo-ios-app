import SwiftUI
import SwiftData
import FirebaseAuth

struct TripListView: View {
    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @State private var isPresentingCreateFlow = false

    var body: some View {
        Group {
            if trips.isEmpty {
                EmptyStateView(
                    iconName: "suitcase",
                    title: "No Trips Yet",
                    message: "Plan your first trip to get started.",
                    actionTitle: "Create a Trip"
                ) {
                    isPresentingCreateFlow = true
                }
            } else {
                List {
                    ForEach(trips) { trip in
                        NavigationLink(value: trip) {
                            TripCardView(
                                name: trip.name,
                                location: trip.location,
                                theme: trip.theme,
                                startDate: trip.startDate,
                                endDate: trip.endDate,
                                status: trip.status
                            )
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(
                            EdgeInsets(
                                top: 6,
                                leading: 16,
                                bottom: 6,
                                trailing: 16
                            )
                        )
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: deleteTrips)
                }
                .listStyle(.plain)
                .refreshable {
                    await refresh()
                }
            }
        }
        .navigationTitle("My Trips")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Trip.self) { trip in
            TripDetailView(trip: trip)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingCreateFlow = true
                } label: {
                    Label("Add Trip", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingCreateFlow) {
            NavigationStack {
                ManualTripFormView(onSaved: { isPresentingCreateFlow = false })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isPresentingCreateFlow = false }
                        }
                    }
            }
        }
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(trips[index])
        }
    }

    private func refresh() async {
        guard let uid = authService.firebaseUser?.uid else { return }
        await TripDiscoveryService.refreshMemberTrips(uid: uid, localTrips: trips, modelContext: modelContext)
    }
}
