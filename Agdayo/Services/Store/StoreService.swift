import Foundation
import Observation
import StoreKit

/// Something the free version limits, and what the unlock gives in its place.
enum PaidFeature: String, Identifiable {
    case moreTrips
    case bigGroups
    case dailyBudgetReport
    case startPolls
    case addIdeas
    case photoAlbum
    case planMyDay
    case liveLocation
    case recapExport

    var id: String { rawValue }

    /// Shown at the top of the unlock screen when this is what the person ran into.
    var reason: String {
        switch self {
        case .moreTrips: return "Free includes \(StoreService.freeTripLimit) trips. Unlock for unlimited trips."
        case .bigGroups: return "Free trips hold up to \(StoreService.freeMemberLimit) people. Unlock for bigger groups."
        case .dailyBudgetReport: return "The daily budget report is part of the full unlock."
        case .startPolls: return "Starting polls is part of the full unlock."
        case .addIdeas: return "Adding ideas is part of the full unlock."
        case .photoAlbum: return "The shared photo album is part of the full unlock."
        case .planMyDay: return "Plan My Day is part of the full unlock."
        case .liveLocation: return "Sharing your live location is part of the full unlock."
        case .recapExport: return "Exporting trip recaps and maps is part of the full unlock."
        }
    }
}

/// Whether this person has the full version — bought it, or bought the app back
/// when it was a paid download — and the purchase flow itself.
///
/// Everything is checked on the device with StoreKit; there's no server. Nothing
/// is ever taken away from someone who paid for the app before it went free.
@Observable
@MainActor
final class StoreService {
    /// The in-app purchase's ID in App Store Connect (non-consumable).
    nonisolated static let productID = "albert.Agdayo.fullunlock"

    /// The app was a paid download up to the build before this one. Anyone whose
    /// first build is lower than this number paid for it and is unlocked for free.
    /// Every build before the free version used build number 1, so this must stay
    /// higher than any build shipped while the app was paid.
    nonisolated static let freeVersionFirstBuild = 100

    nonisolated static let freeTripLimit = 2
    nonisolated static let freeMemberLimit = 3

    private static let grandfatheredKey = "store.isGrandfathered"

    private(set) var product: Product?
    private(set) var hasPurchased = false
    private(set) var isGrandfathered: Bool
    private(set) var isPurchasing = false
    private(set) var isLoadingProduct = false
    private(set) var errorMessage: String?
    /// True once the first check of what the person owns has finished, so the
    /// app doesn't act on a "free" answer that's only there because it hasn't asked yet.
    private(set) var hasLoadedEntitlements = false

    /// Which version to show, for demos and testing. Only honored in debug builds
    /// and TestFlight — never in the App Store release, where it's ignored and hidden.
    enum DemoMode: String, CaseIterable, Identifiable {
        case real = "Real"
        case free = "Free"
        case full = "Full"
        var id: String { rawValue }
    }

    private static let demoModeKey = "store.demoMode"

    var demoMode: DemoMode {
        didSet { UserDefaults.standard.set(demoMode.rawValue, forKey: Self.demoModeKey) }
    }

    /// True once the App Store says this isn't a production install (TestFlight or Xcode).
    private(set) var isTestEnvironment = false

    var allowsDemoMode: Bool {
        #if DEBUG
        return true
        #else
        return isTestEnvironment
        #endif
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        // Remembered once confirmed, so a paying customer who opens the app
        // offline isn't treated as a free user until the App Store answers.
        isGrandfathered = UserDefaults.standard.bool(forKey: Self.grandfatheredKey)
        demoMode = DemoMode(rawValue: UserDefaults.standard.string(forKey: Self.demoModeKey) ?? "") ?? .real
    }

    var isUnlocked: Bool {
        if allowsDemoMode {
            switch demoMode {
            case .free: return false
            case .full: return true
            case .real: break
            }
        }
        return hasPurchased || isGrandfathered
    }

    // MARK: Lifecycle

    /// Call once at launch: loads the price, works out what the person owns, and
    /// keeps listening for purchases made elsewhere (another device, Family Sharing).
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self.updateEntitlements()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        await loadProduct()
        await updateEntitlements()
    }

    // MARK: Gating helpers

    /// Runs `action` if the full version is unlocked; otherwise calls `onLocked`
    /// (which should show the unlock screen for `feature`).
    func require(_ feature: PaidFeature, onLocked: (PaidFeature) -> Void, perform action: () -> Void) {
        if isUnlocked { action() } else { onLocked(feature) }
    }

    /// Trips the person made themselves (not ones they joined) — the ones the free limit counts.
    static func ownedTripCount(in trips: [Trip], uid: String?) -> Int {
        trips.filter { $0.ownerUID == nil || $0.ownerUID == uid }.count
    }

    func canCreateTrip(existing trips: [Trip], uid: String?) -> Bool {
        isUnlocked || Self.ownedTripCount(in: trips, uid: uid) < Self.freeTripLimit
    }

    // MARK: Purchase

    func purchase() async {
        guard let product else { return }
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    await updateEntitlements()
                case .unverified:
                    errorMessage = "The App Store couldn't verify this purchase. Please try again."
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Only ever called from a button the person taps — restoring asks for their
    /// App Store password, so it must never happen on its own.
    func restore() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = error.localizedDescription
        }
        await updateEntitlements()
        if !isUnlocked, errorMessage == nil {
            errorMessage = "No previous purchase was found for this Apple Account."
        }
    }

    // MARK: Private

    private func loadProduct() async {
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            product = nil
        }
    }

    private func updateEntitlements() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                purchased = true
            }
        }
        hasPurchased = purchased

        if await checkGrandfathered() {
            isGrandfathered = true
            UserDefaults.standard.set(true, forKey: Self.grandfatheredKey)
        }
        hasLoadedEntitlements = true
    }

    /// True if this Apple Account got the app before it went free. Only trusted
    /// from the real App Store: TestFlight and Xcode builds always report the
    /// same placeholder version, which would unlock every tester.
    private func checkGrandfathered() async -> Bool {
        do {
            guard case .verified(let appTransaction) = try await AppTransaction.shared else { return false }
            isTestEnvironment = appTransaction.environment != .production
            guard appTransaction.environment == .production,
                  let firstBuild = Int(appTransaction.originalAppVersion) else { return false }
            return firstBuild < Self.freeVersionFirstBuild
        } catch {
            return false
        }
    }
}
