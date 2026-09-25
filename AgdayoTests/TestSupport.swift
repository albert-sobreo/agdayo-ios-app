import Foundation
import SwiftData
@testable import Agdayo

/// Fresh in-memory `ModelContext` per call, mirroring the schema in
/// `AgdayoApp.sharedModelContainer` so relationship inverses (e.g.
/// `Trip.activities`) are wired up the same way they are in the app.
@MainActor
func makeTestContext() -> ModelContext {
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
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [configuration])
    return ModelContext(container)
}
