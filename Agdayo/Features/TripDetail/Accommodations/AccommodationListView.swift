import SwiftUI
import SwiftData

struct AccommodationListView: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    /// Live query scoped to this trip rather than a `trip.accommodations`
    /// traversal — see `ItineraryTimelineView`'s equivalent property for why.
    @Query private var accommodations: [Accommodation]

    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var editingAccommodation: Accommodation?

    init(trip: Trip, memberProfiles: [AppUserProfile] = []) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        let tripID = trip.id
        _accommodations = Query(filter: #Predicate<Accommodation> { $0.trip?.id == tripID })
    }

    private var sorted: [Accommodation] {
        accommodations.sorted { $0.startDate < $1.startDate }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                EmptyStateView(
                    iconName: "bed.double",
                    title: "No Accommodations Yet",
                    message: "Add where you're staying during this trip.",
                    actionTitle: "Add Accommodation",
                    action: { isAdding = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandPalette.canvas.ignoresSafeArea())
            } else {
                List {
                    ForEach(sorted) { accommodation in
                        Button {
                            editingAccommodation = accommodation
                        } label: {
                            AccommodationRow(accommodation: accommodation, accentColor: trip.theme.accentColor, currencyCode: trip.currency)
                        }
                        .buttonStyle(.plain)
                        .moneyRow()
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(BrandPalette.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("Accommodations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Add Accommodation", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            AccommodationEditSheet(trip: trip, memberProfiles: memberProfiles)
        }
        .sheet(item: $editingAccommodation) { accommodation in
            AccommodationEditSheet(trip: trip, editingAccommodation: accommodation, memberProfiles: memberProfiles)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let accommodation = sorted[index]
            if trip.ownerUID != nil {
                let tripID = trip.id
                let accommodationID = accommodation.id
                Task {
                    try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "accommodations", docID: accommodationID)
                }
            }
            modelContext.delete(accommodation)
        }
    }
}

/// One stay as a card: icon badge, name and place, then dates, rooms and cost.
private struct AccommodationRow: View {
    let accommodation: Accommodation
    let accentColor: Color
    let currencyCode: String

    var body: some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    MoneyIconBadge(systemName: "bed.double.fill", accentColor: accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accommodation.name)
                            .font(AppFont.barlowCondensed(24, weight: .semibold))
                            .foregroundStyle(.primary)
                        if !accommodation.location.isEmpty {
                            Label(accommodation.location, systemImage: "mappin.and.ellipse")
                                .font(AppFont.outfit(12, relativeTo: .caption))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    PillTag(text: accommodation.type.displayName, background: accentColor.opacity(0.15), foreground: accentColor)
                }

                Divider()

                HStack(alignment: .top) {
                    stat("STAY", dateRangeText, detail: nightsText)
                    Spacer()
                    stat("CHECK IN / OUT", "\(accommodation.checkInTime) / \(accommodation.checkOutTime)", detail: roomsText)
                    if accommodation.totalCost > 0 {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            label("TOTAL")
                            MoneyAmount(text: accommodation.totalCost.formattedCurrency(code: currencyCode), size: 22)
                        }
                    }
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(AppFont.outfit(10, weight: .semibold, relativeTo: .caption2))
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }

    private func stat(_ title: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            label(title)
            Text(value)
                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(.primary)
            Text(detail)
                .font(AppFont.outfit(11, relativeTo: .caption2))
                .foregroundStyle(.secondary)
        }
    }

    private var dateRangeText: String {
        let formatter = Date.FormatStyle().month(.abbreviated).day()
        return "\(accommodation.startDate.formatted(formatter)) – \(accommodation.endDate.formatted(formatter))"
    }

    private var nightsText: String {
        let nights = max(Calendar.current.dateComponents([.day], from: accommodation.startDate, to: accommodation.endDate).day ?? 0, 0)
        return nights == 1 ? "1 night" : "\(nights) nights"
    }

    private var roomsText: String {
        accommodation.numberOfRooms == 1 ? "1 room" : "\(accommodation.numberOfRooms) rooms"
    }
}
