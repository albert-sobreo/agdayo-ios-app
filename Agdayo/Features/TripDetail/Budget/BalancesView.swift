import SwiftData
import SwiftUI

/// Aggregates "who paid" / "who's splitting" across Activities,
/// Accommodations, and TransportSegments (via `ExpenseBalanceService`) into
/// each member's net balance and a minimal settle-up list. Only reachable
/// when there's more than one member — see `TripSectionsRow.showsBalances`.
struct BalancesView: View {
    let trip: Trip
    let memberProfiles: [AppUserProfile]

    @Environment(\.modelContext) private var modelContext
    @State private var syncErrorMessage: String?

    private var balances: [(profile: AppUserProfile, amount: Double)] {
        let net = ExpenseBalanceService.balances(for: trip)
        return memberProfiles
            .map { ($0, net[$0.uid] ?? 0) }
            .sorted { $0.1 > $1.1 }
    }

    private var settlements: [ExpenseSettlement] {
        ExpenseBalanceService.settlements(for: trip)
    }

    private var paymentHistory: [Settlement] {
        trip.settlements.sorted { $0.date > $1.date }
    }

    private func profile(for uid: String) -> AppUserProfile? {
        memberProfiles.first { $0.uid == uid }
    }

    var body: some View {
        List {
            Section("Balances") {
                if balances.allSatisfy({ abs($0.amount) < 0.01 }) {
                    Text("No shared expenses yet. Add a paid-by and split to an Activity, Accommodation, or Transport segment to start tracking balances.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(balances, id: \.profile.uid) { entry in
                        BalanceRow(profile: entry.profile, amount: entry.amount, currency: trip.currency, accentColor: trip.theme.accentColor)
                    }
                }
            }

            if !settlements.isEmpty {
                Section {
                    ForEach(settlements) { settlement in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(profile(for: settlement.fromUID)?.displayName ?? "Someone")
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                    Text(profile(for: settlement.toUID)?.displayName ?? "someone")
                                }
                                Text(settlement.amount.formattedCurrency(code: trip.currency))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Mark as Paid") {
                                markAsPaid(settlement)
                            }
                            .buttonStyle(.bordered)
                            .tint(trip.theme.accentColor)
                        }
                    }
                } header: {
                    Text("Settle Up")
                }
            }

            if !paymentHistory.isEmpty {
                Section("Payment History") {
                    ForEach(paymentHistory) { settlement in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(profile(for: settlement.fromUID)?.displayName ?? "Someone")
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                    Text(profile(for: settlement.toUID)?.displayName ?? "someone")
                                }
                                Text(settlement.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(settlement.amount.formattedCurrency(code: trip.currency))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deletePayments)
                }
            }
        }
        .navigationTitle("Balances")
        .navigationBarTitleDisplayMode(.inline)
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
        if isSettled { return "Settled up" }
        return amount > 0 ? "Gets back" : "Owes"
    }

    private var statusColor: Color {
        if isSettled { return .secondary }
        return amount > 0 ? .green : .red
    }

    var body: some View {
        HStack(spacing: 12) {
            MemberAvatarView(profile: profile, diameter: 36, tintColor: accentColor)
            Text(profile.displayName)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(abs(amount).formattedCurrency(code: currency))
                    .foregroundStyle(statusColor)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
