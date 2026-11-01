import SwiftUI
import StoreKit

extension View {
    /// Shows the unlock screen when `feature` is set. Each screen that can hit a
    /// limit attaches its own, because a sheet can't open over another sheet from
    /// the app's root.
    func paywall(_ feature: Binding<PaidFeature?>) -> some View {
        sheet(item: feature) { feature in
            PaywallView(feature: feature)
        }
    }
}

/// The one-time ₱99 unlock: what's included, the price, buy and restore.
struct PaywallView: View {
    var feature: PaidFeature?

    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let benefits: [(icon: String, text: String)] = [
        ("infinity", "Unlimited trips and bigger groups"),
        ("chart.bar.xaxis", "Daily budget report"),
        ("chart.bar", "Polls and an ideas list for the group"),
        ("photo.on.rectangle.angled", "Shared photo album"),
        ("wand.and.stars", "Plan My Day"),
        ("location", "Share your live location with the group"),
        ("square.and.arrow.up", "Export trip recaps and maps")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.appPrimary)
                        Text("Unlock Agdayo")
                            .font(AppFont.barlowCondensed(32, weight: .bold))
                            .textCase(.uppercase)
                            .tracking(1)
                        if let feature {
                            Text(feature.reason)
                                .font(AppFont.outfit(14, relativeTo: .subheadline))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(benefits, id: \.text) { benefit in
                            HStack(spacing: 14) {
                                Image(systemName: benefit.icon)
                                    .font(.body)
                                    .foregroundStyle(Color.appPrimary)
                                    .frame(width: 26)
                                Text(benefit.text)
                                    .font(AppFont.outfit(15, relativeTo: .body))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

                    VStack(spacing: 12) {
                        purchaseButton

                        Button("Restore Purchases") {
                            Task { await store.restore() }
                        }
                        .font(AppFont.outfit(14, weight: .medium, relativeTo: .subheadline))
                        .foregroundStyle(.primary)
                        .disabled(store.isPurchasing)

                        if let message = store.errorMessage {
                            Text(message)
                                .font(AppFont.outfit(12, relativeTo: .caption))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Text("One-time purchase. No subscription. Everyone you invite can still join and take part for free.")
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            }
            .background(BrandPalette.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                        .foregroundStyle(.primary)
                }
            }
        }
        // Close as soon as it's unlocked, by purchase or restore.
        .onChange(of: store.isUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
        .task {
            if store.product == nil { await store.refresh() }
        }
    }

    @ViewBuilder
    private var purchaseButton: some View {
        if let product = store.product {
            Button {
                Task { await store.purchase() }
            } label: {
                if store.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text("Unlock for \(product.displayPrice)")
                }
            }
            .buttonStyle(.appPrimary)
            .disabled(store.isPurchasing)
        } else if store.isLoadingProduct {
            ProgressView()
                .padding(.vertical, 12)
        } else {
            VStack(spacing: 8) {
                Text("Couldn't load the price. Check your connection and try again.")
                    .font(AppFont.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") {
                    Task { await store.refresh() }
                }
                .buttonStyle(.appSecondary)
            }
        }
    }

}
