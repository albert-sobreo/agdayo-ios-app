import SwiftUI
import MapKit
import CoreLocation
import FirebaseFirestore
import FirebaseAuth

/// Plots every activity with a coordinate on a map, with style switching
/// (standard/imagery/hybrid, replacing Leaflet's 3 tile layers) and a
/// bottom scroller to focus on a specific activity, mirroring SheetMap.vue.
/// For shared trips, also offers opt-in live location sharing: while this
/// screen is open, a member can broadcast their current position so other
/// members see them move in real time (foreground-only, last point only).
struct TripMapView: View {
    let trip: Trip

    @Environment(AuthService.self) private var authService

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var mapStyleOption: MapStyleOption = .standard
    @State private var selectedActivityID: UUID?

    @State private var locationTracker = LiveLocationTracker()
    @State private var isSharingLocation = false
    @State private var memberLocations: [String: LiveLocationDTO] = [:]
    @State private var memberProfiles: [String: AppUserProfile] = [:]
    @State private var locationListener: ListenerRegistration?
    @State private var selectedMemberUID: String?

    @State private var routeMode: MKDirectionsTransportType = .automobile
    @State private var routeSegments: [RouteSegment] = []

    private var activitiesWithCoordinates: [Activity] {
        trip.activities.filter { $0.coordinate != nil }.sorted { $0.date < $1.date }
    }

    private var routeTaskKey: String {
        "\(routeMode.rawValue)-" + activitiesWithCoordinates.map(\.id.uuidString).joined(separator: ",")
    }

    private var currentUID: String? {
        authService.firebaseUser?.uid
    }

    private var canShareLocation: Bool {
        trip.ownerUID != nil && authService.isSignedIn
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition, selection: $selectedActivityID) {
                ForEach(routeSegments) { segment in
                    MapPolyline(segment.polyline)
                        .stroke(
                            trip.theme.accentColor,
                            style: StrokeStyle(
                                lineWidth: 4,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }

                ForEach(activitiesWithCoordinates) { activity in
                    if let coordinate = activity.coordinate {
                        Marker(activity.title, coordinate: coordinate)
                            .tint(trip.theme.accentColor)
                            .tag(activity.id)
                    }
                }

                ForEach(Array(memberLocations.values), id: \.uid) { location in
                    let profile = memberProfiles[location.uid]
                    let title = (profile?.displayName ?? "Member")
                        + (location.uid == currentUID ? " (You)" : "")

                    Annotation(
                        title,
                        coordinate: CLLocationCoordinate2D(
                            latitude: location.latitude,
                            longitude: location.longitude
                        )
                    ) {
                        MemberLocationPin(
                            profile: profile,
                            accentColor: trip.theme.accentColor
                        )
                    }
                }
            }
            .mapStyle(mapStyleOption.mapStyle)
            .onAppear(perform: fitAllActivities)
            .task(id: routeTaskKey) {
                await loadRoutes()
            }

            // Floating controls at the bottom
            ZStack(alignment: .bottom) {
                // Progressive fade behind the controls
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black.opacity(0.05), location: 0.35),
                        .init(color: .black.opacity(0.25), location: 0.7),
                        .init(color: .black.opacity(0.45), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)

                VStack(spacing: 10) {
                    if !memberLocations.isEmpty {
                        MemberLocationScroller(
                            locations: Array(memberLocations.values)
                                .sorted { $0.uid < $1.uid },
                            profiles: memberProfiles,
                            accentColor: trip.theme.accentColor,
                            currentUID: currentUID,
                            selectedUID: selectedMemberUID,
                            onSelect: focusMember
                        )
                    }

                    if !activitiesWithCoordinates.isEmpty {
                        ActivityScroller(
                            activities: activitiesWithCoordinates,
                            selectedActivityID: $selectedActivityID,
                            onSelect: focus
                        )
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: startListeningIfShared)
        .onDisappear(perform: teardown)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if canShareLocation {
                    ShareLocationButton(
                        isSharing: isSharingLocation,
                        action: toggleSharing
                    )
                }

                if activitiesWithCoordinates.count > 1 {
                    RouteModePickerButton(selection: $routeMode)
                }

                MapStylePickerButton(selection: $mapStyleOption)
            }
        }
    }

    private func fitAllActivities() {
        let coordinates = activitiesWithCoordinates.compactMap { $0.coordinate }
        guard !coordinates.isEmpty else { return }
        let rect = coordinates.reduce(MKMapRect.null) { partial, coordinate in
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            return partial.union(pointRect)
        }
        cameraPosition = .rect(rect.insetBy(dx: -rect.width * 0.2 - 500, dy: -rect.height * 0.2 - 500))
    }

    private func focus(_ activity: Activity) {
        guard let coordinate = activity.coordinate else { return }
        selectedActivityID = activity.id
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600))
        }
    }

    private func focusMember(_ location: LiveLocationDTO) {
        selectedMemberUID = location.uid
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                latitudinalMeters: 600, longitudinalMeters: 600
            ))
        }
    }

    private func loadRoutes() async {
        let ordered = activitiesWithCoordinates
        guard ordered.count > 1 else {
            routeSegments = []
            return
        }
        var segments: [RouteSegment] = []
        for (from, to) in zip(ordered, ordered.dropFirst()) {
            guard let fromCoordinate = from.coordinate, let toCoordinate = to.coordinate else { continue }
            if let route = try? await TravelEstimateService.route(from: fromCoordinate, to: toCoordinate, transportType: routeMode) {
                segments.append(RouteSegment(id: "\(from.id)-\(to.id)", polyline: route.polyline))
            }
        }
        routeSegments = segments
    }

    private func startListeningIfShared() {
        guard trip.ownerUID != nil, locationListener == nil else { return }
        let tripID = trip.id
        locationListener = FirestoreCollectionSync.listen(tripID: tripID, collection: "liveLocations", as: LiveLocationDTO.self) { type, uid, dto in
            Task { @MainActor in
                switch type {
                case .added, .modified:
                    guard let dto else { return }
                    memberLocations[uid] = dto
                    if memberProfiles[uid] == nil {
                        if let profile = try? await UserDirectoryService.fetchProfile(uid: uid) {
                            memberProfiles[uid] = profile
                        }
                    }
                case .removed:
                    memberLocations.removeValue(forKey: uid)
                }
            }
        }
    }

    private func toggleSharing() {
        guard let uid = currentUID else { return }
        isSharingLocation.toggle()
        if isSharingLocation {
            locationTracker.requestPermission()
            let tripID = trip.id
            locationTracker.start { coordinate in
                Task {
                    try? await FirestoreCollectionSync.push(
                        tripID: tripID, collection: "liveLocations", docID: uid,
                        data: LiveLocationDTO(uid: uid, latitude: coordinate.latitude, longitude: coordinate.longitude, updatedAt: .now)
                    )
                }
            }
        } else {
            stopSharing(uid: uid)
        }
    }

    private func stopSharing(uid: String) {
        locationTracker.stop()
        let tripID = trip.id
        Task { try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "liveLocations", docID: uid) }
    }

    private func teardown() {
        locationListener?.remove()
        locationListener = nil
        if isSharingLocation, let uid = currentUID {
            stopSharing(uid: uid)
            isSharingLocation = false
        }
    }
}

private struct RouteSegment: Identifiable {
    let id: String
    let polyline: MKPolyline
}

private struct RouteModePickerButton: View {
    @Binding var selection: MKDirectionsTransportType

    var body: some View {
        Menu {
            Button("Driving") { selection = .automobile }
            Button("Walking") { selection = .walking }
            Button("Transit") { selection = .transit }
            Button("Cycling") { selection = .cycling }
        } label: {
            Image(systemName: selection.sfSymbolName)
                .padding(8)
        }
        .accessibilityLabel("Route Mode")
    }
}

private struct ShareLocationButton: View {
    let isSharing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSharing ? "location.fill" : "location.slash")
                .foregroundStyle(isSharing ? .green : .primary)
                .padding(8)
        }
        .accessibilityLabel(isSharing ? "Stop Sharing Location" : "Share My Location")
    }
}

private struct MemberLocationPin: View {
    let profile: AppUserProfile?
    let accentColor: Color

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MemberAvatarView(profile: profile, diameter: 36, tintColor: accentColor)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)

            Circle()
                .fill(.green)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(.white, lineWidth: 2))
        }
    }
}

/// Shared photo-or-monogram avatar, used for both the map pin and the
/// member scroller chip below.
private struct MemberAvatarView: View {
    let profile: AppUserProfile?
    let diameter: CGFloat
    let tintColor: Color

    private var monogram: String {
        String(profile?.displayName.first ?? "?").uppercased()
    }

    var body: some View {
        Group {
            if let photoURL = profile?.photoURL, let url = URL(string: photoURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    monogramView
                }
            } else {
                monogramView
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }

    private var monogramView: some View {
        Circle()
            .fill(tintColor)
            .overlay(
                Text(monogram)
                    .font(AppFont.outfit(diameter * 0.4, weight: .bold, relativeTo: .caption))
                    .foregroundStyle(.white)
            )
    }
}

private struct MemberLocationScroller: View {
    let locations: [LiveLocationDTO]
    let profiles: [String: AppUserProfile]
    let accentColor: Color
    let currentUID: String?
    let selectedUID: String?
    let onSelect: (LiveLocationDTO) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(locations, id: \.uid) { location in
                    MemberLocationChip(
                        profile: profiles[location.uid],
                        accentColor: accentColor,
                        isCurrentUser: location.uid == currentUID,
                        isSelected: location.uid == selectedUID
                    ) {
                        onSelect(location)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
        }
        .background(Color(.clear))
    }
}

private struct MemberLocationChip: View {
    let profile: AppUserProfile?
    let accentColor: Color
    let isCurrentUser: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                MemberAvatarView(profile: profile, diameter: 20, tintColor: accentColor)
                Text((profile?.displayName ?? "Member") + (isCurrentUser ? " (You)" : ""))
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassOrStickerControl(
                isSelected: isSelected,
                tint: accentColor.opacity(0.2)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityScroller: View {
    let activities: [Activity]
    @Binding var selectedActivityID: UUID?
    let onSelect: (Activity) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(activities.enumerated()), id: \.element.id) { index, activity in
                    ActivityScrollerChip(
                        number: index + 1,
                        title: activity.title,
                        isSelected: activity.id == selectedActivityID
                    ) {
                        onSelect(activity)
                    }
                }
            }
            .padding()
        }
        .background(Color(.clear))
    }
}

private struct ActivityScrollerChip: View {
    let number: Int
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("\(number)")
                    .font(AppFont.outfit(12, weight: .bold, relativeTo: .caption))
                    .frame(width: 20, height: 20)
                    .background(isSelected ? Color.appPrimary : Color(.systemGray5))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .clipShape(Circle())
                Text(title)
                    .font(AppFont.outfit(12, relativeTo: .caption))
                    .lineLimit(1)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .glassOrStickerControl(
                isSelected: isSelected,
                tint: Color(.secondarySystemBackground)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
