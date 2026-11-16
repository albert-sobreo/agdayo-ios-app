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

    private let locationSharing = LiveLocationSharingCoordinator()
    private let liveActivity = TripLiveActivityCoordinator()
    private let store = StoreService()

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
            TripPoll.self,
            TripIdea.self,
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
    }

    var body: some Scene {
        WindowGroup {
            // Straight to the tabs: no account or intro is needed to start planning.
            RootTabView()
                .appFont()
                .preferredColorScheme(.light)
                .environment(authService)
                .environment(locationSharing)
                .environment(liveActivity)
                .environment(store)
                .task { store.start() }
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
