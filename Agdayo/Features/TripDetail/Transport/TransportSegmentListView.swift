import SwiftUI
import SwiftData

struct TransportSegmentListView: View {
    let trip: Trip
    var memberProfiles: [AppUserProfile] = []

    /// Live query scoped to this trip rather than a `trip.transportSegments`
    /// traversal — see `ItineraryTimelineView`'s equivalent property for why.
    @Query private var segments: [TransportSegment]

    @Environment(\.modelContext) private var modelContext
    @State private var isAdding = false
    @State private var editingSegment: TransportSegment?

    init(trip: Trip, memberProfiles: [AppUserProfile] = []) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        let tripID = trip.id
        _segments = Query(filter: #Predicate<TransportSegment> { $0.trip?.id == tripID })
    }

    private var sorted: [TransportSegment] {
        // `departureDate` only carries the day (its time part is whatever it
        // was saved with), so same-day legs need the "HH:mm" time too.
        segments.sorted { $0.departureDateTime < $1.departureDateTime }
    }

    var body: some View {
        Group {
            if sorted.isEmpty {
                EmptyStateView(
                    iconName: "airplane",
                    title: "No Transport Yet",
                    message: "Add flights, buses, or other ways you'll get around.",
                    actionTitle: "Add Transport",
                    action: { isAdding = true }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(BrandPalette.canvas.ignoresSafeArea())
            } else {
                List {
                    ForEach(sorted) { segment in
                        Button {
                            editingSegment = segment
                        } label: {
                            TransportSegmentRow(segment: segment, dayTitle: trip.dayTitle(for: segment.departureDate), accentColor: trip.theme.accentColor)
                        }
                        .buttonStyle(.plain)
                        .moneyRow()
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await toggleCalendar(for: segment) }
                            } label: {
                                Label(
                                    segment.calendarEventID == nil ? "Add to Calendar" : "Remove from Calendar",
                                    systemImage: segment.calendarEventID == nil ? "calendar.badge.plus" : "calendar.badge.minus"
                                )
                            }
                            .tint(trip.theme.accentColor)
                        }
                    }
                    .onDelete(perform: delete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(BrandPalette.canvas.ignoresSafeArea())
            }
        }
        .navigationTitle("Transport")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isAdding = true } label: {
                    Label("Add Transport", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            TransportSegmentEditSheet(trip: trip, memberProfiles: memberProfiles)
        }
        .sheet(item: $editingSegment) { segment in
            TransportSegmentEditSheet(trip: trip, editingSegment: segment, memberProfiles: memberProfiles)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let segment = sorted[index]
            if trip.ownerUID != nil {
                let tripID = trip.id
                let segmentID = segment.id
                Task {
                    try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "transportSegments", docID: segmentID)
                }
            }
            NotificationScheduler.cancelReminder(forTransportID: segment.id)
            modelContext.delete(segment)
        }
    }

    private func toggleCalendar(for segment: TransportSegment) async {
        if let eventID = segment.calendarEventID {
            await CalendarExportService.removeEvent(identifier: eventID)
            segment.calendarEventID = nil
        } else {
            segment.calendarEventID = await CalendarExportService.addEvent(for: segment)
        }
    }
}

/// One trip leg as a ticket-style card: mode, then where from and where to
/// with times, then booking details and cost.
private struct TransportSegmentRow: View {
    let segment: TransportSegment
    /// "Day 2", or "Before trip"/"After trip" for legs outside the trip's dates.
    let dayTitle: String
    let accentColor: Color

    var body: some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    MoneyIconBadge(systemName: segment.mode.iconName, accentColor: accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(dayTitle)
                            .font(AppFont.outfit(13, weight: .bold, relativeTo: .footnote))
                            .foregroundStyle(accentColor)
                        Text(segment.departureDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(AppFont.outfit(13, weight: .semibold, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    PillTag(text: segment.mode.displayName, background: accentColor.opacity(0.15), foreground: accentColor)
                }

                HStack(alignment: .top, spacing: 8) {
                    endpoint(segment.departureLocation, time: Self.twelveHour(segment.departureTime), alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(accentColor)
                        .padding(.top, 10)
                    endpoint(segment.arrivalLocation, time: Self.twelveHour(segment.arrivalTime), alignment: .trailing)
                }

                if hasDetails {
                    Divider()
                    HStack(spacing: 10) {
                        if let ref = segment.bookingRef, !ref.isEmpty {
                            detail("ticket", ref)
                        }
                        if let seat = segment.seatNumber, !seat.isEmpty {
                            detail("chair", seat)
                        }
                        Spacer()
                        if segment.cost > 0 {
                            MoneyAmount(text: segment.cost.formattedCurrency(code: segment.currency), size: 20)
                        }
                    }
                }
            }
        }
    }

    /// Stored "HH:mm" as "2:30 PM", whatever the phone's clock setting.
    /// Anything that isn't a valid time is shown as typed.
    static func twelveHour(_ time: String?) -> String? {
        guard let time, !time.isEmpty else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return time }
        let hour = parts[0] % 12 == 0 ? 12 : parts[0] % 12
        return String(format: "%d:%02d %@", hour, parts[1], parts[0] < 12 ? "AM" : "PM")
    }

    private var hasDetails: Bool {
        segment.cost > 0 || !(segment.bookingRef ?? "").isEmpty || !(segment.seatNumber ?? "").isEmpty
    }

    /// Time first, in large type, with the place underneath.
    private func endpoint(_ place: String, time: String?, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(time.flatMap { $0.isEmpty ? nil : $0 } ?? "--:--")
                .font(AppFont.barlowCondensed(28, weight: .semibold))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(place.isEmpty ? "Anywhere" : place)
                .font(AppFont.outfit(14, weight: .semibold, relativeTo: .subheadline))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func detail(_ systemName: String, _ text: String) -> some View {
        Label(text, systemImage: systemName)
            .font(AppFont.outfit(12, weight: .medium, relativeTo: .caption))
            .foregroundStyle(.secondary)
    }
}
