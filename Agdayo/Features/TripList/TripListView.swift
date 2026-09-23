import SwiftUI
import SwiftData
import FirebaseAuth

struct TripListView: View {
    /// Set by `RootTabView` after a deep-link join finishes (that sheet is
    /// presented from the root, outside this view's own `NavigationStack`)
    /// so this view can push straight into the newly joined trip.
    @Binding var pendingJoinedTrip: Trip?

    @Query(sort: \Trip.startDate) private var trips: [Trip]
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var authService
    @State private var isPresentingCreateFlow = false
    @State private var isPresentingJoinFlow = false
    @State private var searchText = ""
    // Owned here (rather than by the surrounding `NavigationStack` in
    // `RootTabView`) so leaving a shared trip can pop all the way back to
    // this list instead of just one level, no matter how deep the leave
    // action happened (e.g. from the Members screen).
    @State private var path = NavigationPath()

    private var filteredTrips: [Trip] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return trips }
        return trips.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.location.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if trips.isEmpty {
                    VStack(spacing: 16) {
                        EmptyStateView(
                            iconName: "suitcase",
                            title: "No Trips Yet",
                            message: "Plan your first trip or join a friend's trip with an invite code.",
                            actionTitle: "Create a Trip"
                        ) {
                            isPresentingCreateFlow = true
                        }

                        Button {
                            isPresentingJoinFlow = true
                        } label: {
                            Label("Join with Code", systemImage: "ticket")
                                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.appPrimary)
                    }
                } else if filteredTrips.isEmpty {
                    EmptyStateView(
                        iconName: "magnifyingglass",
                        title: "No Matching Trips",
                        message: "Try a different name or destination."
                    )
                } else {
                    List {
                        ForEach(filteredTrips) { trip in
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
            .background(BackgroundImageModifier())
            .navigationTitle("My Trips")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search trips")
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip, onLeftTrip: { path = NavigationPath() })
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isPresentingCreateFlow = true
                        } label: {
                            Label("Create Trip", systemImage: "plus")
                        }
                        Button {
                            isPresentingJoinFlow = true
                        } label: {
                            Label("Join Trip with Code", systemImage: "ticket")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
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
            .sheet(isPresented: $isPresentingJoinFlow) {
                JoinTripSheet(onJoined: { trip in path.append(trip) })
            }
            .onChange(of: pendingJoinedTrip) { _, newValue in
                guard let newValue else { return }
                path.append(newValue)
                pendingJoinedTrip = nil
            }
        }
    }

    private func deleteTrips(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredTrips[index])
        }
    }

    private func refresh() async {
        guard let uid = authService.firebaseUser?.uid else { return }
        await TripDiscoveryService.refreshMemberTrips(uid: uid, localTrips: trips, modelContext: modelContext)
    }
}
