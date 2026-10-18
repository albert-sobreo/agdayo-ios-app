import SwiftUI
import MapKit
import SwiftData

struct ActivityDetailView: View {
    let trip: Trip
    let activity: Activity
    let accentColor: Color
    var memberProfiles: [AppUserProfile] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var isEditing = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isTogglingCalendar = false
    @State private var isEditingCost = false
    @State private var costDraft = ""
    @FocusState private var focusedAmountUID: String?

    private var currencyCode: String { activity.costCurrency ?? trip.currency }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let coordinate = activity.coordinate {
                    ActivityMiniMap(coordinate: coordinate, title: activity.title)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.denseCard))
                }

                header

                actionButtons

                detailsCard

                costCard

                if !activity.activityDescription.isEmpty {
                    MoneyCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTES")
                                .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                                .tracking(1.5)
                                .foregroundStyle(.secondary)
                            Text(activity.activityDescription)
                                .font(AppFont.outfit(16, relativeTo: .body))
                        }
                    }
                }
            }
            .padding()
        }
        .background(BrandPalette.canvas.ignoresSafeArea())
        .navigationTitle(activity.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Edit is one tap away; only the destructive action stays in the menu.
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isEditing = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel("Edit")

                Menu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More Options")
            }
        }
        .sheet(isPresented: $isEditing) {
            ActivityEditSheet(trip: trip, editingActivity: activity, memberProfiles: memberProfiles)
        }
        .confirmationDialog("Delete this activity?", isPresented: $isShowingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if trip.ownerUID != nil {
                    let tripID = trip.id
                    let activityID = activity.id
                    Task {
                        try? await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "activities", docID: activityID)
                    }
                }
                NotificationScheduler.cancelReminder(forActivityID: activity.id)
                modelContext.delete(activity)
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            MoneyIconBadge(systemName: activity.iconName, accentColor: accentColor)
            Text(activity.title)
                .font(AppFont.barlowCondensed(30, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Icon-only shortcuts: open in Maps, add to or remove from Calendar.
    private var actionButtons: some View {
        HStack(spacing: 12) {
            if let coordinate = activity.coordinate {
                Button {
                    openInAppleMaps(coordinate: coordinate, name: activity.title)
                } label: {
                    actionIcon("map")
                }
                .accessibilityLabel("Open in Apple Maps")
            }

            Button {
                Task { await toggleCalendar() }
            } label: {
                if isTogglingCalendar {
                    ProgressView()
                        .frame(width: 48, height: 48)
                } else {
                    actionIcon(activity.calendarEventID == nil ? "calendar.badge.plus" : "calendar.badge.minus")
                }
            }
            .disabled(isTogglingCalendar)
            .accessibilityLabel(activity.calendarEventID == nil ? "Add to Calendar" : "Remove from Calendar")

            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
    }

    /// Liquid Glass in the trip's color on iOS 26+, a tinted circle before that.
    @ViewBuilder
    private func actionIcon(_ systemName: String) -> some View {
        let icon = Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 48, height: 48)
        if #available(iOS 26, *) {
            icon
                .foregroundStyle(.white)
                .glassEffect(.regular.tint(accentColor).interactive(), in: Circle())
        } else {
            icon
                .foregroundStyle(accentColor)
                .background(accentColor.opacity(0.14), in: Circle())
        }
    }

    private var detailsCard: some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 14) {
                detailRow("calendar", activity.date.formatted(date: .complete, time: .omitted))
                detailRow("clock", activity.date.formatted(date: .omitted, time: .shortened))
                if !activity.location.isEmpty {
                    detailRow("mappin.and.ellipse", activity.location)
                }
            }
        }
    }

    private func detailRow(_ systemName: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemName)
                .foregroundStyle(accentColor)
                .frame(width: 22)
            Text(text)
                .font(AppFont.outfit(16, relativeTo: .body))
                .foregroundStyle(.primary)
        }
    }

    /// Cost and who paid, both editable in place without opening the edit sheet.
    private var costCard: some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("COST")
                    .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)

                Button {
                    costDraft = activity.cost.map { String($0) } ?? ""
                    isEditingCost = true
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        if let cost = activity.cost {
                            MoneyAmount(text: cost.formattedCurrency(code: currencyCode), size: 34, color: .primary)
                            if let note = activity.costNote, !note.isEmpty {
                                Text(note)
                                    .font(AppFont.outfit(13, relativeTo: .footnote))
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Add cost")
                                .font(AppFont.outfit(16, weight: .semibold, relativeTo: .body))
                                .foregroundStyle(accentColor)
                        }
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(accentColor)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if activity.cost != nil, memberProfiles.count > 1 {
                    Divider()
                    paidByRow
                    Divider()
                    splitSection
                }
            }
        }
        .alert("Cost", isPresented: $isEditingCost) {
            TextField("Amount", text: $costDraft)
                .keyboardType(.decimalPad)
            Button("Save") { saveCost() }
            if activity.cost != nil {
                Button("Remove Cost", role: .destructive) { removeCost() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("In \(currencyCode).")
        }
    }

    private var paidByRow: some View {
        HStack {
            Label("Paid by", systemImage: "person.crop.circle")
                .font(AppFont.outfit(15, relativeTo: .subheadline))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Button {
                    setPaidBy(nil)
                } label: {
                    if activity.paidByUID == nil { Label("Not tracked", systemImage: "checkmark") } else { Text("Not tracked") }
                }
                ForEach(memberProfiles, id: \.uid) { profile in
                    Button {
                        setPaidBy(profile.uid)
                    } label: {
                        if activity.paidByUID == profile.uid {
                            Label(profile.displayName, systemImage: "checkmark")
                        } else {
                            Text(profile.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(memberProfiles.first { $0.uid == activity.paidByUID }?.displayName ?? "Not tracked")
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .subheadline))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(accentColor)
            }
        }
    }

    // MARK: Split

    /// An empty `splitUIDs` means everyone, matching the edit sheet's default.
    private var splitSet: Set<String> {
        activity.splitUIDs.isEmpty ? Set(memberProfiles.map(\.uid)) : Set(activity.splitUIDs)
    }

    private var isCustomSplit: Bool { !activity.splitAmounts.isEmpty }

    private var splitAmountsTotal: Double {
        splitSet.reduce(0) { $0 + (activity.splitAmounts[$1] ?? 0) }
    }

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SPLIT")
                .font(AppFont.outfit(11, weight: .semibold, relativeTo: .caption2))
                .tracking(1.5)
                .foregroundStyle(.secondary)

            if splitSet.count > 1 {
                Picker("Split", selection: customSplitBinding) {
                    Text("Equally").tag(false)
                    Text("By Amount").tag(true)
                }
                .pickerStyle(.segmented)
            }

            ForEach(memberProfiles, id: \.uid) { profile in
                HStack {
                    Button {
                        toggleSplit(profile.uid)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: splitSet.contains(profile.uid) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(splitSet.contains(profile.uid) ? accentColor : Color.secondary)
                            Text(profile.displayName)
                                .font(AppFont.outfit(15, relativeTo: .subheadline))
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if isCustomSplit, splitSet.contains(profile.uid) {
                        TextField("0", value: amountBinding(for: profile.uid), format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedAmountUID, equals: profile.uid)
                            .frame(width: 80)
                    }
                }
            }

            if isCustomSplit, let cost = activity.cost {
                HStack {
                    Text("Split total")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(splitAmountsTotal.formattedCurrency(code: currencyCode)) / \(cost.formattedCurrency(code: currencyCode))")
                        .foregroundStyle(abs(splitAmountsTotal - cost) < 0.01 ? Color.secondary : Color.red)
                }
                .font(AppFont.outfit(13, relativeTo: .footnote))
            }
        }
        .onChange(of: focusedAmountUID) {
            // Sync once an amount field is done, not on every keystroke.
            if focusedAmountUID == nil { pushIfShared() }
        }
    }

    private var customSplitBinding: Binding<Bool> {
        Binding(
            get: { isCustomSplit },
            set: { useCustom in
                if useCustom {
                    let uids = splitSet
                    let total = activity.cost ?? 0
                    let share = uids.isEmpty ? 0 : (total / Double(uids.count) * 100).rounded() / 100
                    activity.splitAmounts = Dictionary(uniqueKeysWithValues: uids.map { ($0, share) })
                } else {
                    activity.splitAmounts = [:]
                }
                activity.splitUIDs = Array(splitSet)
                pushIfShared()
            }
        )
    }

    private func amountBinding(for uid: String) -> Binding<Double> {
        Binding(
            get: { activity.splitAmounts[uid] ?? 0 },
            set: { activity.splitAmounts[uid] = $0 }
        )
    }

    private func toggleSplit(_ uid: String) {
        var uids = splitSet
        if uids.contains(uid) {
            uids.remove(uid)
            activity.splitAmounts.removeValue(forKey: uid)
        } else {
            uids.insert(uid)
            if isCustomSplit { activity.splitAmounts[uid] = 0 }
        }
        activity.splitUIDs = Array(uids)
        pushIfShared()
    }

    private func saveCost() {
        let normalized = costDraft.replacingOccurrences(of: ",", with: "")
        guard let value = Double(normalized), value >= 0 else { return }
        if activity.cost != value {
            // Custom per-person amounts were for the old total; fall back to an even split.
            activity.splitAmounts = [:]
        }
        activity.cost = value
        if activity.costCurrency == nil { activity.costCurrency = trip.currency }
        pushIfShared()
    }

    private func removeCost() {
        activity.cost = nil
        activity.costCurrency = nil
        activity.costNote = nil
        activity.exchangeRateToTripCurrency = nil
        activity.splitAmounts = [:]
        pushIfShared()
    }

    private func setPaidBy(_ uid: String?) {
        activity.paidByUID = uid
        pushIfShared()
    }

    private func pushIfShared() {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let activityID = activity.id
        let dto = activity.dto
        Task {
            try? await FirestoreCollectionSync.push(tripID: tripID, collection: "activities", docID: activityID, data: dto)
        }
    }

    private func openInAppleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = name
        mapItem.openInMaps()
    }

    private func toggleCalendar() async {
        isTogglingCalendar = true
        if let eventID = activity.calendarEventID {
            await CalendarExportService.removeEvent(identifier: eventID)
            activity.calendarEventID = nil
        } else {
            activity.calendarEventID = await CalendarExportService.addEvent(for: activity)
        }
        isTogglingCalendar = false
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
