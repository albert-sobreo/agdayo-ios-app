import SwiftUI

struct CreateTripFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [CreateTripRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                Text("Plan a New Trip")
                    .font(AppFont.outfit(24, weight: .bold))
                Text("Start from scratch, or let AI suggest an itinerary you can review and edit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    path.append(.manual)
                } label: {
                    Label("Create Manually", systemImage: "square.and.pencil")
                }
                .buttonStyle(.appPrimary)

                Button {
                    path.append(.ai)
                } label: {
                    Label("Generate with AI", systemImage: "sparkles")
                }
                .buttonStyle(.appSecondary)
            }
            .padding()
            .navigationTitle("New Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(for: CreateTripRoute.self) { route in
                switch route {
                case .manual:
                    ManualTripFormView(onSaved: dismiss.callAsFunction)
                case .ai:
                    AIItineraryGenerationView(onSaved: dismiss.callAsFunction)
                }
            }
        }
    }
}

private enum CreateTripRoute: Hashable {
    case manual
    case ai
}
