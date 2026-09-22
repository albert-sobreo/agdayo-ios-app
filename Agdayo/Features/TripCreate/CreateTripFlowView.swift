import SwiftUI

struct CreateTripFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [CreateTripRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 16) {
                Text("Plan a New Trip")
                    .font(.title2.bold())
                Text("Start from scratch, or let AI suggest an itinerary you can review and edit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    path.append(.manual)
                } label: {
                    Label("Create Manually", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    path.append(.ai)
                } label: {
                    Label("Generate with AI", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
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
                    ManualTripFormView()
                case .ai:
                    AIItineraryGenerationView()
                }
            }
        }
    }
}

private enum CreateTripRoute: Hashable {
    case manual
    case ai
}
