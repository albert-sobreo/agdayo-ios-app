import SwiftData
import SwiftUI

/// Who chips in for what: every costed activity, stay, ride and expense, with
/// each person's share of it and who paid (see `MemberCostService`). Reached
/// from the Budget screen's Per Person section on trips with more than one person.
struct MemberContributionsView: View {
    let trip: Trip
    let memberProfiles: [AppUserProfile]

    /// Live queries scoped to this trip, like `BalancesView`.
    @Query private var activities: [Activity]
    @Query private var accommodations: [Accommodation]
    @Query private var transportSegments: [TransportSegment]
    @Query private var expenses: [Expense]

    @State private var kind: CostKind = .activities

    init(trip: Trip, memberProfiles: [AppUserProfile]) {
        self.trip = trip
        self.memberProfiles = memberProfiles
        let tripID = trip.id
        _activities = Query(filter: #Predicate<Activity> { $0.trip?.id == tripID })
        _accommodations = Query(filter: #Predicate<Accommodation> { $0.trip?.id == tripID })
        _transportSegments = Query(filter: #Predicate<TransportSegment> { $0.trip?.id == tripID })
        _expenses = Query(filter: #Predicate<Expense> { $0.trip?.id == tripID })
    }

    private var accent: Color { trip.theme.accentColor }

    private var rows: [CostContribution] {
        MemberCostService.contributions(
            kind,
            activities: activities,
            accommodations: accommodations,
            transportSegments: transportSegments,
            expenses: expenses,
            currency: trip.currency,
            memberUIDs: memberProfiles.map(\.uid)
        )
    }

    private func money(_ amount: Double) -> String {
        amount.formattedCurrency(code: trip.currency)
    }

    var body: some View {
        let rows = self.rows
        List {
            Section {
                Picker("Kind", selection: $kind) {
                    ForEach(CostKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .moneyRow()

                if rows.isEmpty {
                    Text("No \(kind.title.lowercased()) with a cost yet.")
                        .font(AppFont.outfit(14, relativeTo: .body))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .moneyRow()
                } else {
                    totalsCard(rows).moneyRow()
                }
            }

            if !rows.isEmpty {
                Section {
                    ForEach(rows) { row in
                        itemCard(row).moneyRow()
                    }
                } header: {
                    MoneySectionHeader(title: kind.title, iconName: kind.iconName, accentColor: accent)
                } footer: {
                    Text("Shares follow each cost's split. A cost with no split is shared evenly by everyone on the trip.")
                        .font(AppFont.outfit(12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BrandPalette.canvas.ignoresSafeArea())
        .navigationTitle("Who Chips In")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Each person's total for the selected kind.
    private func totalsCard(_ rows: [CostContribution]) -> some View {
        var byPerson: [String: Double] = [:]
        for row in rows {
            for (uid, share) in row.shares { byPerson[uid, default: 0] += share }
        }
        let total = rows.reduce(0) { $0 + ($1.total ?? 0) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(kind.title) total")
                    .trackedLabel(11, color: BrandPalette.maroon.opacity(0.75))
                Spacer()
                MoneyAmount(text: money(total), size: 28, color: BrandPalette.maroon)
            }
            ForEach(memberProfiles, id: \.uid) { profile in
                HStack {
                    Text(profile.displayName)
                        .font(AppFont.outfit(14, relativeTo: .body))
                        .lineLimit(1)
                    Spacer()
                    Text(money(byPerson[profile.uid] ?? 0))
                        .font(AppFont.outfit(14, weight: .semibold, relativeTo: .body))
                }
                .foregroundStyle(BrandPalette.maroon)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrandPalette.blush, in: RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private func itemCard(_ row: CostContribution) -> some View {
        MoneyCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(AppFont.outfit(15, weight: .semibold, relativeTo: .body))
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    if let total = row.total {
                        MoneyAmount(text: money(total), size: 20)
                    } else {
                        Text("No exchange rate")
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(memberProfiles, id: \.uid) { profile in
                    HStack(spacing: 6) {
                        Text(profile.displayName)
                            .font(AppFont.outfit(13, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if row.paidByUID == profile.uid {
                            PillTag(text: "PAID", background: BrandPalette.mint, foreground: BrandPalette.mintText)
                        }
                        Spacer()
                        if let share = row.shares[profile.uid], share > 0 {
                            Text(money(share))
                                .font(AppFont.outfit(13, weight: .medium, relativeTo: .footnote))
                        } else {
                            Text("–")
                                .font(AppFont.outfit(13, relativeTo: .footnote))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}
