import SwiftUI

/// Reused by `ActivityEditSheet`, `AccommodationEditSheet`, and
/// `TransportSegmentEditSheet` to attach "who paid" + "who's splitting the
/// cost" to a real, specific transaction. Only rendered when there's
/// someone else to split with — a solo trip (or a trip you're the only
/// member of) has nothing to show here.
struct ExpenseSplitSection: View {
    let memberProfiles: [AppUserProfile]
    let totalCost: Double
    let currencyCode: String
    @Binding var paidByUID: String?
    @Binding var splitUIDs: Set<String>
    /// Custom per-uid amounts. Empty means "split `splitUIDs` evenly."
    @Binding var splitAmounts: [String: Double]

    private var isCustomSplit: Bool { !splitAmounts.isEmpty }

    private var splitAmountsTotal: Double {
        splitUIDs.reduce(0) { $0 + (splitAmounts[$1] ?? 0) }
    }

    var body: some View {
        if memberProfiles.count > 1 {
            Section {
                Picker("Paid by", selection: $paidByUID) {
                    Text("Not tracked").tag(String?.none)
                    ForEach(memberProfiles, id: \.uid) { profile in
                        Text(profile.displayName).tag(String?.some(profile.uid))
                    }
                }

                if splitUIDs.count > 1 {
                    Picker("Split", selection: customSplitBinding) {
                        Text("Equally").tag(false)
                        Text("By Amount").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                ForEach(memberProfiles, id: \.uid) { profile in
                    HStack {
                        Button {
                            toggle(profile.uid)
                        } label: {
                            HStack {
                                Image(systemName: splitUIDs.contains(profile.uid) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(splitUIDs.contains(profile.uid) ? Color.appPrimary : .secondary)
                                Text(profile.displayName)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if isCustomSplit, splitUIDs.contains(profile.uid) {
                            TextField("0", value: amountBinding(for: profile.uid), format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                }

                if isCustomSplit {
                    HStack {
                        Text("Split total")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(splitAmountsTotal.formattedCurrency(code: currencyCode)) / \(totalCost.formattedCurrency(code: currencyCode))")
                            .foregroundStyle(abs(splitAmountsTotal - totalCost) < 0.01 ? Color.secondary : Color.red)
                    }
                }
            } header: {
                Text("Split")
            } footer: {
                if isCustomSplit, abs(splitAmountsTotal - totalCost) >= 0.01 {
                    Text("Amounts don't add up to the total cost yet.")
                }
            }
        }
    }

    private var customSplitBinding: Binding<Bool> {
        Binding(
            get: { isCustomSplit },
            set: { useCustom in
                if useCustom {
                    let share = splitUIDs.isEmpty ? 0 : (totalCost / Double(splitUIDs.count) * 100).rounded() / 100
                    splitAmounts = Dictionary(uniqueKeysWithValues: splitUIDs.map { ($0, share) })
                } else {
                    splitAmounts = [:]
                }
            }
        )
    }

    private func amountBinding(for uid: String) -> Binding<Double> {
        Binding(
            get: { splitAmounts[uid] ?? 0 },
            set: { splitAmounts[uid] = $0 }
        )
    }

    private func toggle(_ uid: String) {
        if splitUIDs.contains(uid) {
            splitUIDs.remove(uid)
            splitAmounts.removeValue(forKey: uid)
        } else {
            splitUIDs.insert(uid)
            if isCustomSplit {
                splitAmounts[uid] = 0
            }
        }
    }
}
