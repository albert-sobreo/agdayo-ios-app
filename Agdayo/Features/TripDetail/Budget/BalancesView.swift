import SwiftData
import SwiftUI

/// Aggregates "who paid" / "who's splitting" across Activities,
/// Accommodations, and TransportSegments (via `ExpenseBalanceService`) into
/// each member's net balance and a minimal settle-up list. Only reachable
/// when there's more than one member — see `TripSectionsRow.showsBalances`.
struct BalancesView: View {
    let trip: Trip
    let memberProfiles: [AppUserProfile]

    /// Live queries scoped to this trip rather than relationship traversals
    /// (`trip.activities`, `trip.settlements`, etc.) — see
    /// `ItineraryTimelineView`'s equivalent property for why those don't
    /// reliably refresh live when a child screen inserts a new item.
    @Query private var activities: [Activity]
    @Query private var accommodations: [Accommodation]
    @Query private var transportSegments: [TransportSegment]
    @Query private var expenses: [Expense]
    @Query private var recordedSettlements: [Settlement]

    @Environment(\.modelContext) private var modelContext
    @State private var syncErrorMessage: String?
    /// The payment waiting on "Mark as Paid?" confirmation.
    @State private var settlementToConfirm: ExpenseSettlement?

    init(trip: Trip, memberProfiles: [AppUserProfile]) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        let tripID = trip.id
        _activities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID })
        _accommodations = Query(filter: #Predicate<Accommodation> { $0.trip?.id == tripID })
        _transportSegments = Query(filter: #Predicate<TransportSegment> { $0.trip?.id == tripID })
        _expenses = Query(filter: #Predicate<Expense> { $0.trip?.id == tripID })
        _recordedSettlements = Query(filter: #Predicate<Settlement> { $0.trip?.id == tripID })
    }

    private var balances: [(profile: AppUserProfile, amount: Double)] {
        let net = ExpenseBalanceService.balances(
            activities: activities, accommodations: accommodations, transportSegments: transportSegments,
            expenses: expenses, recordedSettlements: recordedSettlements, currency: trip.currency
        )
        return memberProfiles
            .map { ($0, net[$0.uid] ?? 0) }
            .sorted { $0.1 > $1.1 }
    }

    private var settlements: [ExpenseSettlement] {
        ExpenseBalanceService.settlements(
            activities: activities, accommodations: accommodations, transportSegments: transportSegments,
            expenses: expenses, recordedSettlements: recordedSettlements, currency: trip.currency
        )
    }

    private var paymentHistory: [Settlement] {
        recordedSettlements.sorted { $0.date > $1.date }
    }

    private func profile(for uid: String) -> AppUserProfile? {
        memberProfiles.first { $0.uid == uid }
    }

    // MARK: Design

    private var accent: Color { trip.theme.accentColor }

    private var hasSharedExpenses: Bool {
        !balances.allSatisfy { abs($0.amount) < 0.01 } || !paymentHistory.isEmpty
    }

    private var outstanding: Double {
        settlements.reduce(0) { $0 + $1.amount }
    }

    /// The summary at the top: what's left to settle, or that everything is.
    private var heroCard: some View {
        let settled = settlements.isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(settled ? "Balances" : "To settle")
                    .trackedLabel(11, color: settled && hasSharedExpenses ? BrandPalette.mintText : BrandPalette.maroon.opacity(0.75))
                Spacer()
                if settled && hasSharedExpenses {
                    PillTag(text: "All settled", background: BrandPalette.mint, foreground: BrandPalette.mintText, icon: "checkmark")
                }
            }

            if !hasSharedExpenses {
                Text("No shared expenses yet")
                    .font(AppFont.barlowCondensed(30, weight: .semibold))
                    .foregroundStyle(BrandPalette.maroon)
                Text("Add a paid-by and split to an activity, stay, transport segment or expense to start tracking who owes whom.")
                    .font(AppFont.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(BrandPalette.maroon.opacity(0.85))
            } else if settled {
                Text("Everyone is square")
                    .font(AppFont.barlowCondensed(40, weight: .semibold))
                    .foregroundStyle(BrandPalette.mintText)
                Text("\(paymentHistory.count) payment\(paymentHistory.count == 1 ? "" : "s") recorded.")
                    .font(AppFont.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(BrandPalette.mintText.opacity(0.85))
            } else {
                MoneyAmount(text: outstanding.formattedCurrency(code: trip.currency), size: 52, color: BrandPalette.maroon)
                Text("\(settlements.count) payment\(settlements.count == 1 ? "" : "s") to settle up")
                    .font(AppFont.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(BrandPalette.maroon.opacity(0.85))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (settled && hasSharedExpenses ? BrandPalette.mint.opacity(0.55) : BrandPalette.blush),
            in: RoundedRectangle(cornerRadius: AppRadius.card)
        )
    }

    private func header(_ title: String, _ icon: String) -> some View {
        MoneySectionHeader(title: title, iconName: icon, accentColor: accent)
    }

    /// Who paid whom, stacked so a long name gets its own line instead of
    /// being truncated beside the other one.
    private func payment(from fromUID: String, to toUID: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(profile(for: fromUID)?.displayName ?? "Someone")
                .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                Text(profile(for: toUID)?.displayName ?? "someone")
                    .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var body: some View {
        List {
            Section {
                heroCard.moneyRow()
            }

            if hasSharedExpenses {
                Section {
                    ForEach(balances, id: \.profile.uid) { entry in
                        BalanceRow(profile: entry.profile, amount: entry.amount, currency: trip.currency, accentColor: accent)
                            .moneyRow()
                    }
                } header: {
                    header("Balances", "person.2")
                }
            }

            if !settlements.isEmpty {
                Section {
                    ForEach(settlements) { settlement in
                        MoneyCard {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    payment(from: settlement.fromUID, to: settlement.toUID)
                                    MoneyAmount(text: settlement.amount.formattedCurrency(code: trip.currency), size: 26, color: BrandPalette.maroon)
                                }
                                Spacer(minLength: 8)
                                Button {
                                    settlementToConfirm = settlement
                                } label: {
                                    Text("Mark paid")
                                        .font(AppFont.outfit(13, weight: .bold, relativeTo: .footnote))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .foregroundStyle(.white)
                                        .background(accent, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .moneyRow()
                    }
                } header: {
                    header("Settle Up", "arrow.left.arrow.right")
                }
            }

            if !paymentHistory.isEmpty {
                Section {
                    ForEach(paymentHistory) { settlement in
                        MoneyCard {
                            HStack(spacing: 12) {
                                MoneyIconBadge(systemName: "checkmark", accentColor: BrandPalette.mintText)
                                VStack(alignment: .leading, spacing: 2) {
                                    payment(from: settlement.fromUID, to: settlement.toUID)
                                    Text(settlement.date, style: .date)
                                        .font(AppFont.outfit(12, relativeTo: .caption))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                MoneyAmount(text: settlement.amount.formattedCurrency(code: trip.currency), size: 20)
                            }
                        }
                        .moneyRow()
                    }
                    .onDelete(perform: deletePayments)
                } header: {
                    header("Payment History", "clock.arrow.circlepath")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BrandPalette.canvas.ignoresSafeArea())
        .navigationTitle("Balances")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Mark as paid?",
            isPresented: Binding(
                get: { settlementToConfirm != nil },
                set: { if !$0 { settlementToConfirm = nil } }
            ),
            titleVisibility: .visible,
            presenting: settlementToConfirm
        ) { settlement in
            Button("Mark as Paid") {
                markAsPaid(settlement)
            }
            Button("Cancel", role: .cancel) {}
        } message: { settlement in
            Text("\(profile(for: settlement.fromUID)?.displayName ?? "Someone") paid \(profile(for: settlement.toUID)?.displayName ?? "someone") \(settlement.amount.formattedCurrency(code: trip.currency)). This is recorded for everyone on the trip.")
        }
        .alert("Couldn't Sync", isPresented: syncErrorMessageBinding) {
            Button("OK") {}
        } message: {
            Text(syncErrorMessage ?? "")
        }
    }

    private var syncErrorMessageBinding: Binding<Bool> {
        Binding(get: { syncErrorMessage != nil }, set: { if !$0 { syncErrorMessage = nil } })
    }

    private func markAsPaid(_ settlement: ExpenseSettlement) {
        let record = Settlement(fromUID: settlement.fromUID, toUID: settlement.toUID, amount: settlement.amount, trip: trip)
        modelContext.insert(record)
        pushIfShared(record)
    }

    private func deletePayments(at offsets: IndexSet) {
        for index in offsets {
            let record = paymentHistory[index]
            pushDeleteIfShared(record)
            modelContext.delete(record)
        }
    }

    private func pushIfShared(_ record: Settlement) {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let recordID = record.id
        let dto = record.dto
        Task {
            do {
                try await FirestoreCollectionSync.push(tripID: tripID, collection: "settlements", docID: recordID, data: dto)
            } catch {
                syncErrorMessage = "This payment was saved on this device only — it failed to sync: \(error.localizedDescription)"
            }
        }
    }

    private func pushDeleteIfShared(_ record: Settlement) {
        guard trip.ownerUID != nil else { return }
        let tripID = trip.id
        let recordID = record.id
        Task {
            do {
                try await FirestoreCollectionSync.pushDelete(tripID: tripID, collection: "settlements", docID: recordID)
            } catch {
                syncErrorMessage = "Couldn't remove this payment from the shared trip: \(error.localizedDescription)"
            }
        }
    }
}

private struct BalanceRow: View {
    let profile: AppUserProfile
    let amount: Double
    let currency: String
    let accentColor: Color

    private var isSettled: Bool { abs(amount) < 0.01 }

    private var statusText: String {
        if isSettled { return "Settled" }
        return amount > 0 ? "Gets back" : "Owes"
    }

    private var pillBackground: Color {
        if isSettled { return BrandPalette.cardSurface }
        return amount > 0 ? BrandPalette.mint : BrandPalette.blush
    }

    private var pillForeground: Color {
        if isSettled { return .secondary }
        return amount > 0 ? BrandPalette.mintText : BrandPalette.maroon
    }

    private var amountColor: Color {
        if isSettled { return .secondary }
        return amount > 0 ? BrandPalette.mintText : BrandPalette.maroon
    }

    var body: some View {
        MoneyCard {
            HStack(spacing: 12) {
                MemberAvatarView(profile: profile, diameter: 44, tintColor: accentColor)
                VStack(alignment: .leading, spacing: 6) {
                    Text(profile.displayName)
                        .font(AppFont.outfit(16, weight: .semibold, relativeTo: .body))
                    PillTag(text: statusText, background: pillBackground, foreground: pillForeground)
                }
                Spacer(minLength: 8)
                MoneyAmount(
                    text: abs(amount).formattedCurrency(code: currency),
                    size: 28,
                    color: amountColor
                )
            }
        }
    }
}

/// Same photo-or-monogram avatar pattern used in `MemberRowView`/`TripMapView`.
private struct MemberAvatarView: View {
    let profile: AppUserProfile
    let diameter: CGFloat
    let tintColor: Color

    private var monogram: String {
        String(profile.displayName.first ?? "?").uppercased()
    }

    var body: some View {
        Group {
            if let photoURL = profile.photoURL, let url = URL(string: photoURL) {
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
