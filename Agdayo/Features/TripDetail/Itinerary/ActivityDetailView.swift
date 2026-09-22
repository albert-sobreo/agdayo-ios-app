import SwiftUI
import MapKit
import SwiftData

struct ActivityDetailView: View {
    let activity: Activity
    let accentColor: Color

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let coordinate = activity.coordinate {
                    ActivityMiniMap(coordinate: coordinate, title: activity.title)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.denseCard))
                }

                HStack(spacing: 10) {
                    Image(systemName: activity.iconName)
                        .font(.title2)
                        .foregroundStyle(accentColor)
                    Text(activity.title)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                }

                Label(activity.date.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    .foregroundStyle(.secondary)

                if !activity.location.isEmpty {
                    Label(activity.location, systemImage: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                }

                if let cost = activity.cost {
                    HStack {
                        Label(cost.formattedCurrency(code: activity.costCurrency ?? "PHP"), systemImage: "wallet.pass")
                        if let note = activity.costNote, !note.isEmpty {
                            Text("· \(note)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !activity.activityDescription.isEmpty {
                    Text(activity.activityDescription)
                        .font(.body)
                }

                if let coordinate = activity.coordinate {
                    Button {
                        openInAppleMaps(coordinate: coordinate, name: activity.title)
                    } label: {
                        Label("Open in Apple Maps", systemImage: "map")
                    }
                    .buttonStyle(.appSecondary)
                }
            }
            .padding()
        }
        .navigationTitle(activity.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ActivityEditSheet(trip: activity.trip ?? Trip(name: "", location: "", startDate: .now, endDate: .now), editingActivity: activity)
        }
        .confirmationDialog("Delete this activity?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                modelContext.delete(activity)
                dismiss()
            }
        }
    }

    private func openInAppleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = name
        mapItem.openInMaps()
    }
}

private struct ActivityMiniMap: View {
    let coordinate: CLLocationCoordinate2D
    let title: String

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
            Marker(title, coordinate: coordinate)
        }
        .allowsHitTesting(false)
    }
}
