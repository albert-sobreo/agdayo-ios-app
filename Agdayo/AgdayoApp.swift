//
//  AgdayoApp.swift
//  Agdayo
//
//  Created by Jan Albert Sobreo on 9/22/26.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct AgdayoApp: App {
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
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        Self.configureNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
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
