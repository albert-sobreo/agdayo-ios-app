//
//  AgdayoApp.swift
//  Agdayo
//
//  Created by Jan Albert Sobreo on 9/22/26.
//

import SwiftUI
import SwiftData
import UIKit
import FirebaseCore
import GoogleSignIn

struct AppFontModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(AppFont.outfit(16, relativeTo: .body))
    }
}

extension View {
    func appFont() -> some View {
        modifier(AppFontModifier())
    }
}

@main
struct AgdayoApp: App {
    /// Lazily-evaluated static, so accessing it below is guaranteed to run
    /// `FirebaseApp.configure()` exactly once. Needed because stored-property
    /// default values (like `authService` below) are evaluated before a
    /// struct's custom `init()` body runs — without this, `AuthService.init()`
    /// would call `Auth.auth()` before Firebase was configured and crash.
    private static let firebaseBootstrap: Void = {
        FirebaseApp.configure()
    }()

    private let authService: AuthService = {
        _ = AgdayoApp.firebaseBootstrap
        return AuthService()
    }()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Trip.self,
            Activity.self,
            Accommodation.self,
            BudgetCategory.self,
            PreparationTask.self,
            TransportSegment.self,
            DayNote.self,
            UserProfile.self,
            Settlement.self,
        ])
        // UI tests pass `-UITestReset` so each run starts from an empty
        // store instead of accumulating trips left by earlier runs.
        let isUITestRun = ProcessInfo.processInfo.arguments.contains("-UITestReset")
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITestRun)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        Self.configureNavigationBarAppearance()
        Self.resetOnboardingStateForUITestsIfNeeded()
    }

    /// Companion to `sharedModelContainer`'s own reset above — `hasCompletedOnboarding`
    /// lives in `UserDefaults`, not the SwiftData store, so a UI test run needs both
    /// cleared for every run to actually start at `OnboardingView`.
    private static func resetOnboardingStateForUITestsIfNeeded() {
        guard ProcessInfo.processInfo.arguments.contains("-UITestReset") else { return }
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }

    var body: some Scene {
        WindowGroup {
            RootContainerView()
                .appFont()
                .preferredColorScheme(.light)
                .environment(authService)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Applies the Outfit typeface to every navigation bar title app-wide,
    /// matching the web app's near-universal `.outfit` body font — without
    /// needing to restyle every screen's `.navigationTitle` individually.
    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.titleTextAttributes = [
            .font: UIFont(name: "Outfit-SemiBold", size: 17) ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        appearance.largeTitleTextAttributes = [
            .font: UIFont(name: "Outfit-ExtraBold", size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
}

/// Shows `OnboardingView` once, on first launch, before `RootTabView` —
/// independent of sign-in state, since the app itself doesn't require an
/// account to start planning a trip.
private struct RootContainerView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            RootTabView()
        } else {
            OnboardingView(onFinish: { hasCompletedOnboarding = true })
        }
    }
}
